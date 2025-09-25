extends Node2D

@onready var tilemap: TileMap = $TileMap
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var spawn_position: Vector2 = Vector2.ZERO
@export var hud_scene: PackedScene = preload("res://scenes/hud.tscn")
@export var defender_hud_scene: PackedScene = preload("res://scenes/defender_hud.tscn")
@export var can_scene: PackedScene = preload("res://scenes/can.tscn")
@export var can_spawn_position: Vector2 = Vector2.ZERO
@export var ui_manager_scene: PackedScene = preload("res://scenes/ui_manager.tscn")
@export var network_player_scene: PackedScene = preload("res://scenes/networked_player.tscn")

var _hud: Node = null
var _hud_connected: bool = false
var _attacker_spawn_global: Vector2 = Vector2.ZERO
var _defender_spawn_global: Vector2 = Vector2.ZERO
var _round_can_hit: bool = false
var _attackers_used: Dictionary = {}
var _slipper_seq: int = 0
var _owner_slippers: Dictionary = {}

func _ready() -> void:
	# If game is set to SINGLEPLAYER, ensure no multiplayer peer is active (clear leftovers)
	if Engine.has_singleton("GameConfig"):
		if GameConfig.mode == GameConfig.Mode.SINGLEPLAYER and multiplayer.multiplayer_peer != null:
			print("[World] Clearing leftover multiplayer peer for SINGLEPLAYER mode")
			multiplayer.multiplayer_peer = null
	
	# Debug: Print current mode
	var is_net = _is_networked()
	print("[World] Starting world - Networked: ", is_net, " | Peer: ", multiplayer.multiplayer_peer)
	# Ensure the TileMap is in the expected group for the Player camera limits
	if tilemap and not tilemap.is_in_group("world_tilemap"):
		tilemap.add_to_group("world_tilemap")

	# Only instantiate offline Player 1 when NOT networked to avoid duplicates in LAN
	if not _is_networked():
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

	# LAN must have NO AI; remove any Defender AI if present when networked
	if _is_networked():
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

	# Ensure HUD exists; connect to offline or network local player when available
	if _hud == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		# Create appropriate HUD based on mode and role
		_hud = _create_appropriate_hud()
		layer.add_child(_hud)

	if not _is_networked():
		var the_player: Node = get_node_or_null("TileMap/player")
		if the_player == null:
			# fallback: search tree
			the_player = get_tree().current_scene.find_child("player", true, false)
		if the_player:
			_connect_hud_to_player(the_player)
	else:
		# Try to connect to local networked player now; if not found, listen for it
		var np := _find_local_networked_player()
		if np:
			_connect_hud_to_player(np)
		else:
			get_tree().node_added.connect(_on_node_added_connect_hud)


func _is_networked() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null

func _setup_networked_play() -> void:
	print("[World] Setting up networked play - removing offline players")
	# Remove any offline players from the scene
	var p1 := get_node_or_null("TileMap/player")
	if p1 and p1 is Node2D:
		print("[World] Removing Player 1 for networked mode")
		_attacker_spawn_global = (p1 as Node2D).global_position
		p1.queue_free()
	var p2 := get_node_or_null("TileMap/player 2")
	if p2 and p2 is Node2D:
		print("[World] Removing Player 2 for networked mode")
		_defender_spawn_global = (p2 as Node2D).global_position
		p2.queue_free()

	# Create a MultiplayerSpawner that will own spawned players
	var spawner: MultiplayerSpawner = get_node_or_null("NetworkSpawner")
	if spawner == null:
		spawner = MultiplayerSpawner.new()
		spawner.name = "NetworkSpawner"
		spawner.spawn_path = NodePath(".")
		spawner.spawn_limit = 10
		add_child(spawner)
	# Register spawnable scenes (safe to call multiple times)
	if ResourceLoader.exists("res://scenes/networked_player.tscn"):
		spawner.add_spawnable_scene("res://scenes/networked_player.tscn")
	if ResourceLoader.exists("res://scenes/slipper.tscn"):
		spawner.add_spawnable_scene("res://scenes/slipper.tscn")
	# Can is present in the scene (world.tscn); it will replicate via its MultiplayerSynchronizer

	# Connect multiplayer signals for dynamic joins/leaves
	if not multiplayer.peer_connected.is_connected(self._on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(self._on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.server_disconnected.is_connected(self._on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Only the server spawns players and the can, but wait for roles to be set first
	if multiplayer.is_server():
		print("[World] Server waiting for role assignment before spawning players")
		# Roles should already be set by multiplayer_lobby.gd before scene change
		call_deferred("_spawn_all_network_players")
		call_deferred("_setup_can_authority")
	# All peers ensure the local Can node has server authority set (safe if already set)
	call_deferred("_setup_can_authority")

func _spawn_all_network_players() -> void:
	print("[World] Spawning all network players with roles")
	if not multiplayer.is_server():
		return
	
	# Get all peer IDs (server + clients)
	var all_peers: Array[int] = [1]  # Server is always peer 1
	for pid in multiplayer.get_peers():
		all_peers.append(pid)
	
	print("[World] All peers to spawn: ", all_peers)
	
	# Get roles from GameConfig
	var roles: Dictionary = {}
	if Engine.has_singleton("GameConfig"):
		roles = GameConfig.roles if "roles" in GameConfig else {}
	# If roles are missing or do not match player count, assign now (server authoritative)
	if roles.is_empty() or roles.size() != all_peers.size():
		roles = _assign_player_roles()
	else:
		# Ensure all clients know their roles
		rpc("_rpc_update_roles_client_side", roles)
	print("[World] Roles assigned: ", roles)

	# Build attacker-local indices so attackers spread neatly at the attacker spawn
	var attackers: Array = []
	for pid in all_peers:
		if String(roles.get(pid, "thrower")).to_lower() == "thrower":
			attackers.append(pid)
	attackers.sort()
	var attacker_index_by_peer: Dictionary = {}
	for j in range(attackers.size()):
		attacker_index_by_peer[attackers[j]] = j

	# Spawn each player with their assigned role (avoid duplicates)
	for i in range(all_peers.size()):
		var peer_id = all_peers[i]
		if get_node_or_null("Player_%s" % peer_id) != null:
			print("[World] Skipping spawn for peer ", peer_id, " (already exists)")
			continue
		var role: String = String(roles.get(peer_id, "thrower"))  # Default to thrower
		var atk_idx: int = int(attacker_index_by_peer.get(peer_id, -1))
		print("[World] Spawning peer ", peer_id, " as ", role, " atk_idx=", atk_idx)
		_spawn_network_player_with_role(peer_id, atk_idx, role)

	# Start round state (server only)
	_round_begin_state()

func _assign_player_roles() -> Dictionary:
	# Server-authoritative role assignment:
	# - 2 players: host (peer 1) = 'thrower', client = 'defender'
	# - 3+ players: randomly choose 1 defender; rest are 'thrower'
	if not multiplayer.is_server():
		return {}
	# Build peer list (server + clients)
	var all_peers: Array[int] = [1]
	for pid in multiplayer.get_peers():
		all_peers.append(pid)
	all_peers.sort()
	var roles: Dictionary = {}
	var count := all_peers.size()
	if count == 2:
		for pid in all_peers:
			roles[pid] = "thrower" if pid == 1 else "defender"
	elif count >= 3:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var defender_peer: int = all_peers[rng.randi_range(0, all_peers.size() - 1)]
		for pid in all_peers:
			roles[pid] = "defender" if pid == defender_peer else "thrower"
	else:
		roles[1] = "thrower"
	# Persist and broadcast
	if Engine.has_singleton("GameConfig"):
		GameConfig.clear_roles()
		GameConfig.roles = roles.duplicate(true)
	rpc("_rpc_update_roles_client_side", roles)
	return roles

func _roles_have_one_defender(roles: Dictionary) -> bool:
	# Helper to ensure exactly one defender is present in the roles map
	var count := 0
	for pid in roles.keys():
		if String(roles[pid]).to_lower() == "defender":
			count += 1
	return count == 1

func _setup_can_authority() -> void:
	# Ensure the server (peer 1) is the authority for the Can so its sync properties replicate
	var can := _find_any_can()
	if can:
		can.set_multiplayer_authority(1)
		var sync := can.get_node_or_null("MultiplayerSynchronizer")
		if sync:
			sync.set_multiplayer_authority(1)

func _spawn_network_can() -> void:
	if not multiplayer.is_server():
		return
	if can_scene == null:
		return
	var spawner: MultiplayerSpawner = get_node_or_null("NetworkSpawner")
	if spawner == null:
		return
	var can := can_scene.instantiate()
	can.name = "NetworkCan"
	can.set_multiplayer_authority(multiplayer.get_unique_id())
	var sync := can.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(multiplayer.get_unique_id())
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	parent_node.add_child(can)
	var spawn := can_spawn_position
	if spawn == Vector2.ZERO:
		spawn = _compute_default_can_spawn()
	if tilemap:
		can.global_position = tilemap.to_global(spawn)
	else:
		can.global_position = spawn
	if "sync_position" in can:
		can.set("sync_position", can.global_position)
	spawner.spawn(can)

func _spawn_network_player_with_role(peer_id: int, index: int, role: String) -> void:
	var spawner: MultiplayerSpawner = get_node_or_null("NetworkSpawner")
	if spawner == null or network_player_scene == null:
		return

	# Always instance locally and add to scene, then replicate via spawner
	var player_inst: Node2D = network_player_scene.instantiate()
	player_inst.name = "Player_%s" % peer_id
	
	# Set authority on the player and its synchronizer before first sync
	player_inst.set_multiplayer_authority(peer_id)
	var sync := player_inst.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(peer_id)
	
	# Set role BEFORE adding to scene
	if "role" in player_inst:
		player_inst.set("role", role)
		print("[World] Set role ", role, " for player ", peer_id)
	
	# Choose spawn by role (attacker from P1 spot, defender from P2 spot)
	var spawn_pos := _compute_network_spawn(index)
	if role.to_lower() == "defender" and _defender_spawn_global != Vector2.ZERO:
		spawn_pos = _defender_spawn_global
	elif role.to_lower() == "thrower" and _attacker_spawn_global != Vector2.ZERO:
		spawn_pos = _attacker_spawn_global
	# Fallback if cached points are missing: place by thirds of playfield
	if spawn_pos == Vector2.ZERO:
		spawn_pos = _fallback_spawn_by_role(role)
	# Spread attackers around attacker spawn based on their attacker-local index
	if role.to_lower() == "thrower" and index >= 0:
		spawn_pos += _attacker_offset_for(index)
	print("[World] Spawning role ", role, " at ", spawn_pos)
	
	# Add to the world before spawning for network replication
	add_child(player_inst)
	player_inst.global_position = spawn_pos
	# Initialize sync_position so remote sides don't lerp to (0,0)
	if "sync_position" in player_inst:
		player_inst.set("sync_position", spawn_pos)

	# Tell all clients to spawn this player locally
	rpc("_rpc_spawn_remote_player", peer_id, role, spawn_pos)
	# Ensure the newly spawned owner's camera becomes current on their client
	rpc_id(peer_id, "_rpc_focus_local_camera")
	# Host also ensures its own camera is focused when spawning its player
	if peer_id == multiplayer.get_unique_id():
		var cam_host: Camera2D = player_inst.get_node_or_null("Camera2D")
		if cam_host:
			cam_host.enabled = true
			cam_host.make_current()

@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_remote_player(peer_id: int, role: String, spawn_pos: Vector2) -> void:
	# Only clients perform this; the server already has the node
	if multiplayer.is_server():
		return
	if network_player_scene == null:
		return
	if get_node_or_null("Player_%s" % peer_id) != null:
		return
	var player_inst: Node2D = network_player_scene.instantiate()
	player_inst.name = "Player_%s" % peer_id
	add_child(player_inst)
	player_inst.global_position = spawn_pos
	if "sync_position" in player_inst:
		player_inst.set("sync_position", spawn_pos)
	if "role" in player_inst:
		player_inst.set("role", role)
	# Preserve authority so the local client can control their own player
	player_inst.set_multiplayer_authority(peer_id)
	var sync := player_inst.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(peer_id)
	# Ensure camera activates for the local player's instance
	if peer_id == multiplayer.get_unique_id():
		var cam: Camera2D = player_inst.get_node_or_null("Camera2D")
		if cam:
			cam.enabled = true
			cam.make_current()

func _fallback_spawn_by_role(role: String) -> Vector2:
	# Compute left/right thirds of the used TileMap area
	var used_local := _compute_default_spawn() # center by default
	if tilemap:
		var used_rect: Rect2i = tilemap.get_used_rect()
		var ts: Vector2i = tilemap.tile_set.tile_size
		var left_x := float(used_rect.position.x * ts.x)
		var right_x := float((used_rect.position.x + used_rect.size.x) * ts.x)
		var mid_y := float((used_rect.position.y + used_rect.size.y / 2.0) * ts.y)
		var pos_local := Vector2(left_x + (right_x - left_x) * (1.0/3.0), mid_y)
		if role.to_lower() == "defender":
			pos_local = Vector2(left_x + (right_x - left_x) * (2.0/3.0), mid_y)
		return tilemap.to_global(pos_local)
	return used_local

@rpc("any_peer", "call_local", "reliable")
func _rpc_focus_local_camera() -> void:
	# Runs on the client: focus the local player's camera
	var local_name := "Player_%s" % multiplayer.get_unique_id()
	var p := get_node_or_null(local_name)
	if p:
		var cam: Camera2D = p.get_node_or_null("Camera2D")
		if cam:
			cam.enabled = true
			cam.make_current()

func _make_offline_camera_current() -> void:
	# Prefer Player 1's camera
	var cam: Camera2D = get_node_or_null("TileMap/player/Camera2D")
	if cam == null:
		cam = get_tree().current_scene.find_child("Camera2D", true, false)
	if cam:
		cam.enabled = true
		cam.make_current()

func _ensure_offline_players_visible() -> void:
	print("[World] Ensuring offline players are visible...")
	var p1: Node2D = get_node_or_null("TileMap/player")
	if p1:
		print("[World] Found Player 1, making visible")
		p1.visible = true
		p1.z_as_relative = false
		p1.z_index = 200
		var s1: CanvasItem = p1.get_node_or_null("AnimatedSprite2D")
		if s1:
			s1.visible = true
			s1.z_index = 200
	else:
		print("[World] Player 1 not found!")
	
	var p2: Node2D = get_node_or_null("TileMap/player 2")
	if p2:
		print("[World] Found Player 2, making visible")
		p2.visible = true
		p2.z_as_relative = false
		p2.z_index = 200
		var s2: CanvasItem = p2.get_node_or_null("AnimatedSprite2D")
		if s2:
			s2.visible = true
			s2.z_index = 200
	else:
		print("[World] Player 2 not found!")

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
		var parent_node: Node = tilemap if tilemap != null else (self as Node)
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

func _on_peer_connected(peer_id: int) -> void:
	print("[World] Peer connected: ", peer_id)
	if multiplayer.is_server():
		# Avoid duplicate spawn if already present (e.g., spawned during bulk spawn)
		if get_node_or_null("Player_%s" % peer_id) != null:
			print("[World] Peer ", peer_id, " already spawned; skipping")
			return
		# Ensure roles include this peer and exactly one defender; reassign if needed
		var roles: Dictionary = {}
		if Engine.has_singleton("GameConfig"):
			roles = GameConfig.roles if "roles" in GameConfig else {}
		var expected_count := multiplayer.get_peers().size() + 1
		var needs_reassign := roles.is_empty() or not roles.has(peer_id) or roles.size() != expected_count or not _roles_have_one_defender(roles)
		var did_reassign := false
		if needs_reassign:
			roles = _assign_player_roles()
			did_reassign = true
		var role: String = String(roles.get(peer_id, "thrower"))
		
		print("[World] Spawning new peer ", peer_id, " as ", role)
		# Spawn the new player with their role
		var index = multiplayer.get_peers().size()  # Use current peer count as index
		_spawn_network_player_with_role(peer_id, index, role)
		# If we reassigned roles due to this join, reposition everyone and start a fresh round
		if did_reassign:
			_reposition_players_after_role_change()
			_round_begin_state()

func _on_peer_disconnected(peer_id: int) -> void:
	print("[World] Peer disconnected: ", peer_id)
	# Remove the disconnected player
	var player_node = get_node_or_null("Player_%s" % peer_id)
	if player_node:
		player_node.queue_free()
	# Re-evaluate roles to ensure exactly one defender remains
	if multiplayer.is_server():
		var peers_left := multiplayer.get_peers().size() + 1
		if peers_left >= 2:
			_assign_player_roles()
			_reposition_players_after_role_change()
			_round_begin_state()

func _on_server_disconnected() -> void:
	print("[World] Server disconnected")
	# Return to main menu or lobby
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
func _compute_network_spawn(index: int) -> Vector2:
	var base_local := _compute_default_spawn()
	var base_global := tilemap.to_global(base_local) if tilemap else base_local
	var offsets := [Vector2(0,0), Vector2(48,0), Vector2(-48,0), Vector2(0,48), Vector2(0,-48), Vector2(64,64), Vector2(-64,64), Vector2(64,-64), Vector2(-64,-64)]
	var off := Vector2.ZERO
	if index >= 0 and index < offsets.size():
		off = offsets[index]
	return base_global + off

# Old functions removed - using new networking approach above


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_slipper(pos: Vector2, dir: Vector2, power: float, owner_peer_id: int) -> void:
	# Only the server performs the authoritative spawn
	if not multiplayer.is_server():
		return
	# Instance and configure slipper (RPC-based replication)
	var slipper_scene: PackedScene = preload("res://scenes/slipper.tscn") if ResourceLoader.exists("res://scenes/slipper.tscn") else null
	if slipper_scene == null:
		return
	# Enforce single active slipper per owner
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	if _owner_slippers.has(owner_peer_id):
		var existing_name := String(_owner_slippers[owner_peer_id])
		var existing := parent_node.get_node_or_null(existing_name)
		if existing != null:
			return
		else:
			_owner_slippers.erase(owner_peer_id)
	var s: Node2D = slipper_scene.instantiate()
	parent_node.add_child(s)
	if s is Node2D:
		(s as Node2D).global_position = pos
	# Server authoritative physics: set authority to server (peer 1)
	s.set_multiplayer_authority(1)
	var s_sync := s.get_node_or_null("MultiplayerSynchronizer")
	if s_sync:
		s_sync.set_multiplayer_authority(1)
	if s.has_method("init"):
		s.init(dir, power)
	# Give a stable name based on owner to avoid duplicates
	var sl_name := "Slipper_%d" % int(owner_peer_id)
	s.name = sl_name
	_owner_slippers[owner_peer_id] = sl_name
	# Hook despawn signals (server-side)
	if s.has_signal("picked_up"):
		s.connect("picked_up", Callable(self, "_on_network_slipper_picked").bind(owner_peer_id, sl_name))
	if s.has_signal("ai_picked_up"):
		s.connect("ai_picked_up", Callable(self, "_on_network_slipper_ai_picked").bind(sl_name))
	# Tell clients to spawn the slipper locally
	rpc("_rpc_spawn_remote_slipper", sl_name, pos, dir, power)
	# Mark that this attacker has thrown (server authoritative round tracking)
	_on_attacker_threw(owner_peer_id)



func _on_network_slipper_picked(owner_peer_id: int, slipper_name: String) -> void:
	# Server callback when a slipper is picked up: despawn everywhere and restore ammo
	if not multiplayer.is_server():
		return
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	var slipper := parent_node.get_node_or_null(slipper_name)
	if slipper:
		slipper.queue_free()
	_owner_slippers.erase(owner_peer_id)
	rpc("_rpc_despawn_remote_slipper", slipper_name)
	var p := get_node_or_null("Player_%s" % owner_peer_id)
	if p and p.has_method("_rpc_set_ammo"):
		p.rpc_id(owner_peer_id, "_rpc_set_ammo", 1)

func _on_network_slipper_ai_picked(slipper_name: String) -> void:
	# Server callback when AI picks up a slipper: despawn everywhere
	if not multiplayer.is_server():
		return
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	var slipper := parent_node.get_node_or_null(slipper_name)
	if slipper:
		slipper.queue_free()
	for k in _owner_slippers.keys():
		if String(_owner_slippers[k]) == slipper_name:
			_owner_slippers.erase(k)
			break
	rpc("_rpc_despawn_remote_slipper", slipper_name)

@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_remote_slipper(sl_name: String, pos: Vector2, dir: Vector2, power: float) -> void:
	# Clients create the slipper locally with same name and authority
	if multiplayer.is_server():
		return
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	if parent_node.get_node_or_null(sl_name) != null:
		return
	var slipper_scene: PackedScene = preload("res://scenes/slipper.tscn") if ResourceLoader.exists("res://scenes/slipper.tscn") else null
	if slipper_scene == null:
		return
	var s: Node2D = slipper_scene.instantiate()
	s.name = sl_name
	parent_node.add_child(s)
	if s is Node2D:
		(s as Node2D).global_position = pos
	s.set_multiplayer_authority(1)
	var s_sync2 := s.get_node_or_null("MultiplayerSynchronizer")
	if s_sync2:
		s_sync2.set_multiplayer_authority(1)
	if s.has_method("init"):
		s.init(dir, power)

@rpc("any_peer", "call_local", "reliable")
func _rpc_despawn_remote_slipper(slipper_name: String) -> void:
	if multiplayer.is_server():
		return
	var parent_node: Node = tilemap if tilemap != null else (self as Node)
	var slipper := parent_node.get_node_or_null(slipper_name)
	if slipper:
		slipper.queue_free()

func _on_node_added_connect_hud(n: Node) -> void:
	if _hud_connected:
		return
	if n == null:
		return
	# We want the local networked player in LAN mode
	if _is_networked():
		var local_name := "Player_%s" % multiplayer.get_unique_id()
		if n.name == local_name:
			_connect_hud_to_player(n)
			get_tree().node_added.disconnect(_on_node_added_connect_hud)

func _connect_hud_to_player(p: Node) -> void:
	if _hud == null or p == null or _hud_connected:
		return
	
	# Get player role to determine HUD behavior
	var player_role := "thrower"
	if "role" in p:
		player_role = String(p.get("role"))
	
	# Connect appropriate signals based on role
	if player_role.to_lower() == "defender":
		# Defender HUD - connect status updates if available
		if _hud.has_method("set_status"):
			_hud.call("set_status", "Defending")
	else:
		# Thrower HUD - connect ammo signals
		if p.has_signal("ammo_changed") and _hud.has_method("set_ammo"):
			p.connect("ammo_changed", Callable(_hud, "set_ammo"))
			# Initialize HUD now
			if "slippers_available" in p and "MAX_SLIPPERS" in p:
				_hud.call("set_ammo", p.get("slippers_available"), p.get("MAX_SLIPPERS"))
	
	_hud_connected = true

func _find_local_networked_player() -> Node:
	var local_name := "Player_%s" % multiplayer.get_unique_id()
	var n := get_node_or_null(local_name)
	if n:
		return n
	return get_tree().current_scene.find_child(local_name, true, false)

func _create_appropriate_hud() -> Node:
	# Determine local player role to create correct HUD
	var local_role := "thrower"
	if _is_networked():
		var local_peer_id := multiplayer.get_unique_id()
		if Engine.has_singleton("GameConfig"):
			var roles := GameConfig.roles if "roles" in GameConfig else {}
			if roles is Dictionary and roles.has(local_peer_id):
				local_role = String(roles[local_peer_id])
	
	# Create appropriate HUD based on role
	if local_role.to_lower() == "defender" and defender_hud_scene:
		return defender_hud_scene.instantiate()
	elif hud_scene:
		return hud_scene.instantiate()
	else:
		# Fallback: create a basic Control node
		return Control.new()

# _apply_roles_to_players removed - roles now set during spawn
func _has_human_defender() -> bool:
	# Checks GameConfig.roles for a connected peer assigned as defender
	if Engine.has_singleton("GameConfig"):
		var roles := GameConfig.roles if "roles" in GameConfig else {}
		if roles is Dictionary:
			for pid in roles.keys():
				var role_val := String(roles[pid])
				if role_val.to_lower() == "defender":
					# Consider the server (ID 1) and any connected peers
					if pid == 1 or multiplayer.get_peers().has(pid):
						return true
	return false
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
		# Also listen for can hits to manage rounds
		if game_manager.has_signal("can_hit"):
			game_manager.connect("can_hit", Callable(self, "_on_can_hit"))

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
		var parent_node: Node = tilemap if tilemap != null else (self as Node)
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

# === LAN Round/Rotation helpers ===

func _attacker_offset_for(idx: int) -> Vector2:
	# Spread pattern for up to 5 attackers around the attacker spawn
	var pattern := [
		Vector2(0, 0),
		Vector2(0, 48),
		Vector2(0, -48),
		Vector2(48, 24),
		Vector2(48, -24)
	]
	if idx >= 0 and idx < pattern.size():
		return pattern[idx]
	return Vector2.ZERO

func _round_begin_state() -> void:
	# Reset per-round flags and give each attacker exactly 1 ammo
	_round_can_hit = false
	_attackers_used.clear()
	if not multiplayer.is_server():
		return
	var roles: Dictionary = {}
	if Engine.has_singleton("GameConfig"):
		roles = GameConfig.roles if "roles" in GameConfig else {}
	for pid in roles.keys():
		if String(roles[pid]).to_lower() == "thrower":
			var p := get_node_or_null("Player_%s" % int(pid))
			if p and p.has_method("_rpc_set_ammo"):
				p.rpc_id(int(pid), "_rpc_set_ammo", 1)

func _on_attacker_threw(owner_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_attackers_used[owner_peer_id] = true
	if not _round_can_hit and _all_attackers_used():
		var attackers := _get_attackers_list()
		_open_defender_select_for_current_defender(attackers)

func _on_can_hit() -> void:
	# Attacker hit the can. Defender remains the same. Start a fresh round.
	if not multiplayer.is_server():
		return
	_round_can_hit = true
	_round_begin_state()

func _get_attackers_list() -> Array:
	var out: Array = []
	if Engine.has_singleton("GameConfig"):
		var roles := GameConfig.roles if "roles" in GameConfig else {}
		for pid in roles.keys():
			if String(roles[pid]).to_lower() == "thrower":
				out.append(int(pid))
	out.sort()
	return out

func _get_current_defender_id() -> int:
	if Engine.has_singleton("GameConfig"):
		var roles := GameConfig.roles if "roles" in GameConfig else {}
		for pid in roles.keys():
			if String(roles[pid]).to_lower() == "defender":
				return int(pid)
	return -1

func _all_attackers_used() -> bool:
	var attackers := _get_attackers_list()
	if attackers.size() == 0:
		return false
	for pid in attackers:
		if not _attackers_used.has(pid):
			return false
	return true

func _open_defender_select_for_current_defender(attackers: Array) -> void:
	var def_id := _get_current_defender_id()
	if def_id == -1:
		return
	rpc_id(def_id, "_rpc_open_defender_select", attackers)

@rpc("any_peer", "call_local", "reliable")
func _rpc_open_defender_select(attackers: Array) -> void:
	# Runs on the defender client: show selection UI
	var ui := get_tree().current_scene.find_child("UIManager", true, false)
	if ui and ui.has_method("show_defender_select"):
		ui.call("show_defender_select", attackers)
		if ui.has_signal("defender_selected"):
			if not ui.is_connected("defender_selected", Callable(self, "_on_defender_selected_locally")):
				ui.connect("defender_selected", Callable(self, "_on_defender_selected_locally"))

func _on_defender_selected_locally(pid: int) -> void:
	# Defender client requests the server to rotate roles
	rpc("_rpc_request_defender_switch", pid)
	# Hide local UI
	var ui := get_tree().current_scene.find_child("UIManager", true, false)
	if ui and ui.has_method("hide_defender_select"):
		ui.call("hide_defender_select")

@rpc("any_peer", "reliable")
func _rpc_request_defender_switch(selected_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != _get_current_defender_id():
		return
	if not Engine.has_singleton("GameConfig"):
		return
	var roles: Dictionary = GameConfig.roles.duplicate(true)
	var current_def := _get_current_defender_id()
	if current_def == -1:
		return
	# Rotate: selected becomes defender; previous defender becomes attacker
	for pid in roles.keys():
		if int(pid) == selected_peer:
			roles[pid] = "defender"
		elif int(pid) == current_def:
			roles[pid] = "thrower"
	GameConfig.clear_roles()
	GameConfig.roles = roles
	rpc("_rpc_update_roles_client_side", roles)
	_reposition_players_after_role_change()
	_round_begin_state()

@rpc("any_peer", "call_local", "reliable")
func _rpc_update_roles_client_side(new_roles: Dictionary) -> void:
	if Engine.has_singleton("GameConfig"):
		GameConfig.clear_roles()
		GameConfig.roles = new_roles.duplicate(true)

func _reposition_players_after_role_change() -> void:
	if not multiplayer.is_server():
		return
	var roles: Dictionary = GameConfig.roles
	var all_pids: Array = [1]
	for pid in multiplayer.get_peers():
		all_pids.append(pid)
	var attackers: Array = []
	for pid in all_pids:
		if String(roles.get(pid, "thrower")).to_lower() == "thrower":
			attackers.append(pid)
	attackers.sort()
	var idx_by_pid: Dictionary = {}
	for i in range(attackers.size()):
		idx_by_pid[attackers[i]] = i
	for pid in all_pids:
		var p := get_node_or_null("Player_%s" % pid)
		if p and p is Node2D:
			var role := String(roles.get(pid, "thrower"))
			if "role" in p:
				p.set("role", role)
			var spawn := _fallback_spawn_by_role(role)
			if role.to_lower() == "defender" and _defender_spawn_global != Vector2.ZERO:
				spawn = _defender_spawn_global
			elif role.to_lower() == "thrower" and _attacker_spawn_global != Vector2.ZERO:
				spawn = _attacker_spawn_global + _attacker_offset_for(int(idx_by_pid.get(pid, -1)))
			(p as Node2D).global_position = spawn
	# Reset ammo for the new round
	_round_begin_state()
