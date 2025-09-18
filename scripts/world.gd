extends Node2D

@onready var tilemap: TileMap = $TileMap
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var spawn_position: Vector2 = Vector2.ZERO
@export var hud_scene: PackedScene = preload("res://scenes/hud.tscn")

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

func _compute_default_spawn() -> Vector2:
	# Place the player roughly at the center of the used TileMap area
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
