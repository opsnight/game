extends Node2D

@onready var tilemap: TileMap = $TileMap
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var spawn_position: Vector2 = Vector2.ZERO
@export var hud_scene: PackedScene = preload("res://scenes/hud.tscn")
@export var can_scene: PackedScene = preload("res://scenes/can.tscn")
@export var can_spawn_position: Vector2 = Vector2.ZERO
@export var ui_manager_scene: PackedScene = preload("res://scenes/ui_manager.tscn")
@export var network_player_scene: PackedScene = preload("res://scenes/networked_player.tscn")

func _ready() -> void:
	# Ensure the TileMap is in the expected group for the Player camera limits
	if tilemap and not tilemap.is_in_group("world_tilemap"):
		tilemap.add_to_group("world_tilemap")

	# If a player already exists in the scene (e.g., instanced in the .tscn), don't spawn another
	var existing_player := get_node_or_null("TileMap/player")
	if existing_player == null:
		# Instance and place the player
		if player_scene:
			var player := player_scene.instantiate()
			player.name = "player"
			# Add under the TileMap to match your scene layout
			if tilemap:
				tilemap.add_child(player)
			else:
				add_child(player)

			var spawn := spawn_position
			if spawn == Vector2.ZERO:
				spawn = _compute_default_spawn()

			# Convert to global assuming spawn is in the TileMap local space
			if tilemap:
				player.global_position = tilemap.to_global(spawn)
			else:
				player.global_position = spawn

	# Build perimeter walls from the TileMap bounds
	_create_bounds_walls()

	# Ensure a can exists in the scene
	_create_or_place_can()
	_dedupe_cans_keep_rightmost()

	# Always 2 human players: remove any Defender AI if present
	if not _is_networked():
		var existing_defender = get_tree().get_first_node_in_group("defender")
		if existing_defender:
			existing_defender.queue_free()

	# If a multiplayer peer is active, switch to networked player spawning
	if _is_networked():
		_setup_networked_play()

	# Create game manager and UI
	_create_game_systems()

	# Ensure a camera is active and following a player in offline mode
	if not _is_networked():
		_make_offline_camera_current()
		_ensure_offline_players_visible()
	else:
		# In LAN mode, ensure Defender AI exists for gameplay
		_ensure_defender_exists()

	# Ensure HUD exists and is connected to the player ammo signal
	var the_player: Node = get_node_or_null("TileMap/player")
	if the_player == null:
		# fallback: search tree
		the_player = get_tree().current_scene.find_child("player", true, false)
	if the_player and hud_scene:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		var hud := hud_scene.instantiate()
		layer.add_child(hud)
		if the_player.has_signal("ammo_changed") and hud.has_method("set_ammo"):
			the_player.connect("ammo_changed", Callable(hud, "set_ammo"))
			# Initialize HUD with current counts if available
			if "slippers_available" in the_player and "MAX_SLIPPERS" in the_player:
				hud.set_ammo(the_player.slippers_available, the_player.MAX_SLIPPERS)


func _is_networked() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null

func _setup_networked_play() -> void:
	# Remove any offline players from the scene
	var p1 := get_node_or_null("TileMap/player")
	if p1: p1.queue_free()
	var p2 := get_node_or_null("TileMap/player 2")
	if p2: p2.queue_free()

	# Create a MultiplayerSpawner that will own spawned players
	var spawner: MultiplayerSpawner = get_node_or_null("NetworkSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "NetworkSpawner"
		spawner.spawn_path = NodePath(".")
		spawner.spawn_limit = 10
		add_child(spawner)
		# Register the networked player scene for replication
		if ResourceLoader.exists("res://scenes/networked_player.tscn"):
			spawner.add_spawnable_scene("res://scenes/networked_player.tscn")

	# Connect multiplayer signals for dynamic joins/leaves
	if not multiplayer.peer_connected.is_connected(self._on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(self._on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.server_disconnected.is_connected(self._on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Only the server spawns players
	if multiplayer.is_server():
		# Spawn server-controlled player (peer 1)
		_spawn_network_player(1, 0)
		# Spawn for already-connected clients
		for pid in multiplayer.get_peers():
			_spawn_network_player(pid, pid % 8)

func _make_offline_camera_current() -> void:
	# Prefer Player 1's camera
	var cam: Camera2D = get_node_or_null("TileMap/player/Camera2D")
	if cam == null:
		cam = get_tree().current_scene.find_child("Camera2D", true, false)
	if cam:
		cam.enabled = true
		cam.make_current()

func _ensure_offline_players_visible() -> void:
	var p1: Node2D = get_node_or_null("TileMap/player")
	if p1:
		p1.visible = true
		p1.z_as_relative = false
		p1.z_index = 200
		var s1: CanvasItem = p1.get_node_or_null("AnimatedSprite2D")
		if s1:
			s1.visible = true
			s1.z_index = 200
	var p2: Node2D = get_node_or_null("TileMap/player 2")
	if p2:
		p2.visible = true
		p2.z_as_relative = false
		p2.z_index = 200
		var s2: CanvasItem = p2.get_node_or_null("AnimatedSprite2D")
		if s2:
			s2.visible = true
			s2.z_index = 200

func _ensure_defender_exists() -> void:
	# Instance Defender AI if not present
	var def := get_tree().get_first_node_in_group("defender")
	if def != null:
		return
	var path := "res://scenes/defender_ai.tscn"
	if not ResourceLoader.exists(path):
		return
	var ps := load(path)
	if ps and ps is PackedScene:
		var inst: Node2D = ps.instantiate()
		var parent_node: Node = tilemap if tilemap != null else self
		parent_node.add_child(inst)
		# Place defender near the can spawn for now
		var spawn: Vector2 = _compute_default_can_spawn()
		if tilemap:
			inst.global_position = tilemap.to_global(spawn)
		else:
			inst.global_position = spawn
		if inst is CanvasItem:
			(inst as CanvasItem).z_as_relative = false
			(inst as CanvasItem).z_index = 180

func _spawn_network_player(peer_id: int, index: int) -> void:
	var spawner: MultiplayerSpawner = get_node_or_null("NetworkSpawner")
	if spawner == null or network_player_scene == null:
		return
	var player_inst: Node2D = network_player_scene.instantiate()
	player_inst.name = "Player_%s" % peer_id
	# CRITICAL: set authority before spawning/adding
	player_inst.set_multiplayer_authority(peer_id)
	var sync := player_inst.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(peer_id)
	player_inst.global_position = _compute_network_spawn(index)
	# Spawn via MultiplayerSpawner so it replicates to clients
	spawner.spawn(player_inst)

func _compute_network_spawn(index: int) -> Vector2:
	var base_local := _compute_default_spawn()
	var base_global := tilemap.to_global(base_local) if tilemap else base_local
	var offsets := [Vector2(0,0), Vector2(48,0), Vector2(-48,0), Vector2(0,48), Vector2(0,-48), Vector2(64,64), Vector2(-64,64), Vector2(64,-64), Vector2(-64,-64)]
	var off := Vector2.ZERO
	if index >= 0 and index < offsets.size():
		off = offsets[index]
	return base_global + off

func _on_peer_connected(pid: int) -> void:
	if multiplayer.is_server():
		_spawn_network_player(pid, pid % 8)

func _on_peer_disconnected(pid: int) -> void:
	var n := get_node_or_null("Player_%s" % pid)
	if n: n.queue_free()

func _on_server_disconnected() -> void:
	# Client side: optionally return to menu
	pass


func _create_game_systems() -> void:
	# Create GameManager
	var game_manager = Node.new()
	game_manager.name = "GameManager"
	game_manager.add_to_group("game_manager")
	var gm_script = preload("res://scripts/game_manager.gd")
	game_manager.set_script(gm_script)
	add_child(game_manager)
	
	# Create UI Manager
	if ui_manager_scene:
		var ui_manager = ui_manager_scene.instantiate()
		add_child(ui_manager)
		
		# Connect game manager and UI
		if ui_manager.has_method("set_game_manager"):
			ui_manager.set_game_manager(game_manager)
		if game_manager.has_method("set_ui_manager"):
			game_manager.set_ui_manager(ui_manager)

func _reset_round() -> void:
	var p1 := get_node_or_null("TileMap/player")
	var p2 := get_node_or_null("TileMap/player 2")
	# Reset Player 1 to base center, refill slippers, clear aura
	if p1 and p1 is Node:
		if "base_center" in p1 and p1 is Node2D:
			(p1 as Node2D).global_position = p1.base_center
		if "slippers_available" in p1 and "MAX_SLIPPERS" in p1:
			p1.slippers_available = p1.MAX_SLIPPERS
			if p1.has_signal("ammo_changed"):
				p1.ammo_changed.emit(p1.slippers_available, p1.MAX_SLIPPERS)
		if p1.has_method("_stop_aim"):
			p1._stop_aim()
		if "is_vulnerable" in p1:
			p1.is_vulnerable = false
		if p1.has_node("AnimatedSprite2D"):
			p1.get_node("AnimatedSprite2D").modulate = Color(1,1,1)
	# Clear all slippers in the scene
	for n in get_tree().get_nodes_in_group("slipper"):
		if n is Node:
			n.queue_free()
	# Reset can to original position if helper exists
	var can := _find_any_can()
	if can:
		if can.has_method("end_carry"):
			can.end_carry()
		if can.has_method("reset_to_original"):
			can.reset_to_original()
	# Ensure Player 2 stops attack/chase state
	if p2:
		if "can_chase_player" in p2:
			p2.can_chase_player = false
		if "is_attacking" in p2:
			p2.is_attacking = false

func _compute_default_spawn() -> Vector2:
	# Place the player roughly at the center of the used TileMap area
	if tilemap:
		var used_rect: Rect2i = tilemap.get_used_rect()
		var tile_size: Vector2i = tilemap.tile_set.tile_size
		var center_cell: Vector2i = used_rect.position + used_rect.size / 2
		var local_pos: Vector2 = tilemap.map_to_local(center_cell)
		return local_pos + Vector2(tile_size) * 0.5
	return Vector2.ZERO

func _compute_default_can_spawn() -> Vector2:
	# Place can roughly near the center of the playfield
	if tilemap:
		var used_rect: Rect2i = tilemap.get_used_rect()
		var tile_size: Vector2i = tilemap.tile_set.tile_size
		var center_cell: Vector2i = used_rect.position + used_rect.size / 2
		var local_pos: Vector2 = tilemap.map_to_local(center_cell)
		return local_pos + Vector2(tile_size) * 0.5
	return Vector2.ZERO

func _create_bounds_walls() -> void:
	if not tilemap:
		return
	var used_rect: Rect2i = tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return
	var ts: Vector2i = tilemap.tile_set.tile_size
	var left := float(used_rect.position.x * ts.x)
	var top := float(used_rect.position.y * ts.y)
	var right := float((used_rect.position.x + used_rect.size.x) * ts.x)
	var bottom := float((used_rect.position.y + used_rect.size.y) * ts.y)
	var inset := 16.0
	left += inset; top += inset; right -= inset; bottom -= inset

	var walls := StaticBody2D.new()
	walls.name = "Bounds"
	$TileMap.add_child(walls)
	# Helper to make a rectangle CollisionShape2D (local lambda)
	var add_rect := func(center: Vector2, size: Vector2) -> void:
		var shape := RectangleShape2D.new()
		shape.size = size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = center
		walls.add_child(cs)

	var thickness := 24.0
		# Top (place wall just inside the playable area)
	add_rect.call(Vector2((left + right) * 0.5, top + thickness * 0.5), Vector2(right - left, thickness))
	# Bottom
	add_rect.call(Vector2((left + right) * 0.5, bottom - thickness * 0.5), Vector2(right - left, thickness))
	# Left
	add_rect.call(Vector2(left + thickness * 0.5, (top + bottom) * 0.5), Vector2(thickness, bottom - top))
	# Right
	add_rect.call(Vector2(right - thickness * 0.5, (top + bottom) * 0.5), Vector2(thickness, bottom - top))

func _create_or_place_can() -> void:
	if not can_scene:
		return
	var existing_can: Node = _find_any_can()
	if existing_can == null:
		var can: Node2D = can_scene.instantiate()
		var parent_node: Node = tilemap if tilemap != null else self
		parent_node.add_child(can)
		can.name = "Can"
		var spawn: Vector2 = can_spawn_position
		if spawn == Vector2.ZERO:
			spawn = _compute_default_can_spawn()
		if tilemap:
			can.global_position = tilemap.to_global(spawn)
		else:
			can.global_position = spawn

func _find_any_can() -> Node:
	# Prefer group lookup; fallback to deep name search
	var cans := get_tree().get_nodes_in_group("can")
	if cans.size() > 0:
		return cans[0]
	return get_tree().current_scene.find_child("Can", true, false)

func _dedupe_cans_keep_rightmost() -> void:
	# If multiple cans exist (e.g., one manually placed and one auto-spawned),
	# keep the right-most one and remove the rest.
	var cans: Array = []
	for n in get_tree().get_nodes_in_group("can"):
		if n is Node2D:
			cans.append(n)
	# Also include any nodes named 'Can' not in group
	var found := get_tree().current_scene.find_child("Can", true, false)
	if found and found is Node2D and not cans.has(found):
		cans.append(found)
	if cans.size() <= 1:
		return
	var keep: Node2D = cans[0]
	for c in cans:
		if c.global_position.x > keep.global_position.x:
			keep = c
	for c in cans:
		if c != keep:
			c.queue_free()
