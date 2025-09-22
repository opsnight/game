extends Node2D

@onready var tilemap: TileMap = $TileMap
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var spawn_position: Vector2 = Vector2.ZERO
@export var hud_scene: PackedScene = preload("res://scenes/hud.tscn")
@export var can_scene: PackedScene = preload("res://scenes/can.tscn")
@export var can_spawn_position: Vector2 = Vector2.ZERO

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

	# Ensure HUD exists and is connected to the player ammo signal
	var the_player: Node = get_node_or_null("TileMap/player")
	if the_player == null:
		# fallback: search tree
		the_player = get_tree().current_scene.find_child("player", true, false)
	if the_player and hud_scene:
		var layer := CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		var hud := hud_scene.instantiate()
		layer.add_child(hud)
		if the_player.has_signal("ammo_changed") and hud.has_method("set_ammo"):
			the_player.connect("ammo_changed", Callable(hud, "set_ammo"))
			# Initialize HUD with current counts if available
			if "slippers_available" in the_player and "MAX_SLIPPERS" in the_player:
				hud.set_ammo(the_player.slippers_available, the_player.MAX_SLIPPERS)

	# Connect interactions between Player 1 and Player 2
	var p1 := get_node_or_null("TileMap/player")
	var p2 := get_node_or_null("TileMap/player 2")
	if p1 and p2:
		# Player 1 -> Player 2: chase toggles
		if p1.has_signal("slipper_thrown") and p2.has_method("on_player_slipper_thrown"):
			p1.connect("slipper_thrown", Callable(p2, "on_player_slipper_thrown"))
		if p1.has_signal("returned_to_base") and p2.has_method("on_player_returned_to_base"):
			p1.connect("returned_to_base", Callable(p2, "on_player_returned_to_base"))
		# Player 2 -> World: caught player -> swap places
		if p2.has_signal("caught_player"):
			p2.connect("caught_player", Callable(self, "_on_player2_caught_player"))

func _on_player2_caught_player() -> void:
	var p1 := get_node_or_null("TileMap/player")
	var p2 := get_node_or_null("TileMap/player 2")
	if p1 and p2 and p1 is Node2D and p2 is Node2D:
		var pos1 := (p1 as Node2D).global_position
		var pos2 := (p2 as Node2D).global_position
		(p1 as Node2D).global_position = pos2
		(p2 as Node2D).global_position = pos1
		# Reset Player 1 base center to new spot (property exists in player.gd)
		p1.base_center = (p1 as Node2D).global_position
		# Stop chase immediately after swap (property exists in player_2.gd)
		p2.can_chase_player = false

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
	var inset := 8.0
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

	var thickness := 16.0
	# Top
	add_rect.call(Vector2((left + right) * 0.5, top - thickness * 0.5), Vector2(right - left, thickness))
	# Bottom
	add_rect.call(Vector2((left + right) * 0.5, bottom + thickness * 0.5), Vector2(right - left, thickness))
	# Left
	add_rect.call(Vector2(left - thickness * 0.5, (top + bottom) * 0.5), Vector2(thickness, bottom - top))
	# Right
	add_rect.call(Vector2(right + thickness * 0.5, (top + bottom) * 0.5), Vector2(thickness, bottom - top))

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
