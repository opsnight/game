extends RigidBody2D

@export var hit_impulse_scale: float = 1.2
@export var min_impulse: float = 150.0
@export var max_impulse: float = 1200.0
@export var fence_margin: float = 24.0 # keep can inside the fence by this margin

# Remember original spawn to allow resets and knockdown checks
var original_position: Vector2
var is_being_carried: bool = false
var carrier: Node2D = null
@onready var _tilemap: TileMap = get_tree().get_first_node_in_group("world_tilemap")
var _bounds_inset: float = 10.0

func _ready() -> void:
	# Enable contact monitoring so body_entered works on RigidBody2D
	contact_monitor = true
	max_contacts_reported = 8
	# Reduce tunneling through walls
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	gravity_scale = 0.0
	linear_damp = 6.0
	angular_damp = 6.0
	# Help prevent tunneling on hard hits
	set_deferred("continuous_cd", true)
	if not is_in_group("can"):
		add_to_group("can")
	self.body_entered.connect(Callable(self, "_on_body_entered"))
	# Store original spawn
	original_position = global_position

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("slipper"):
		_apply_hit_from(body)

func _apply_hit_from(node: Node) -> void:
	var impulse: Vector2 = Vector2.ZERO
	# Support both old Area2D slippers (velocity) and new RigidBody2D slippers (linear_velocity)
	if "linear_velocity" in node:
		var v: Vector2 = node.linear_velocity
		impulse = v * hit_impulse_scale
	elif "velocity" in node:
		var v2: Vector2 = node.velocity
		impulse = v2 * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - node.global_position)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	if impulse.length() > max_impulse:
		impulse = impulse.limit_length(max_impulse)
	apply_impulse(impulse)

func is_knocked_down(threshold: float = 30.0) -> bool:
	# Consider knocked down if moved sufficiently from original position
	return global_position.distance_to(original_position) > threshold

func reset_to_original() -> void:
	# Put the can back exactly, clear all physics motion
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_position = original_position
	rotation = 0.0
	freeze = false

func begin_carry(by: Node2D) -> void:
	# Freeze physics and attach visually to the carrier
	is_being_carried = true
	carrier = by
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	# Keep as sibling but follow in _process via carrier
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

func end_carry() -> void:
	is_being_carried = false
	carrier = null
	freeze = false
	# Restore collisions (default to all)
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 1)

func _physics_process(delta: float) -> void:
	if is_being_carried and carrier:
		# Follow a point slightly in front of the carrier
		var to_dir := Vector2.DOWN
		if "current_dir" in carrier and carrier.current_dir is String:
			# crude forward vector from 8-dir
			match carrier.current_dir:
				"up": to_dir = Vector2.UP
				"down": to_dir = Vector2.DOWN
				"left": to_dir = Vector2.LEFT
				"right": to_dir = Vector2.RIGHT
				"up_right": to_dir = Vector2(1,-1).normalized()
				"up_left": to_dir = Vector2(-1,-1).normalized()
				"down_right": to_dir = Vector2(1,1).normalized()
				"down_left": to_dir = Vector2(-1,1).normalized()
		global_position = carrier.global_position + to_dir * 20.0
		return

	# Clamp inside world bounds if available
	_clamp_inside_bounds()

func _clamp_inside_bounds() -> void:
	if _tilemap == null:
		# Try to resolve it lazily (parent World adds the group in its _ready)
		_tilemap = get_tree().get_first_node_in_group("world_tilemap")
		if _tilemap == null:
			var root := get_tree().current_scene
			if root:
				for child in root.get_children():
					if child is TileMap:
						_tilemap = child
						break
			if _tilemap == null:
				return
	var used_rect: Rect2i = _tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return
	var ts: Vector2i = _tilemap.tile_set.tile_size
	var left := float(used_rect.position.x * ts.x) + _bounds_inset
	var top := float(used_rect.position.y * ts.y) + _bounds_inset
	var right := float((used_rect.position.x + used_rect.size.x) * ts.x) - _bounds_inset
	var bottom := float((used_rect.position.y + used_rect.size.y) * ts.y) - _bounds_inset
	# Work in TileMap local space for robustness
	var local_pos: Vector2 = (_tilemap.to_local(global_position))
	var clamped := Vector2(clamp(local_pos.x, left, right), clamp(local_pos.y, top, bottom))
	if clamped != local_pos:
		global_position = _tilemap.to_global(clamped)

func hit_from(vel: Vector2, hit_pos: Vector2) -> void:
	# Public API for Area2D (slipper) to notify hits
	var impulse := vel * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - hit_pos)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)
	
	# Notify game manager that can was hit
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("add_score"):
		game_manager.add_score(10)
	
	# Notify defender AI
	var defender = get_tree().get_first_node_in_group("defender")
	if defender and defender.has_method("on_can_hit"):
		defender.on_can_hit()

func restore() -> void:
	# Reset can to upright position and stop movement
	rotation = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
