extends RigidBody2D

@export var hit_impulse_scale: float = 1.2
@export var min_impulse: float = 150.0
@export var max_impulse: float = 1200.0
@export var fence_margin: float = 24.0 # keep can inside the fence by this margin

# Remember original spawn to allow resets and knockdown checks
var original_position: Vector2
var is_being_carried: bool = false
var carrier: Node2D = null

func _ready() -> void:
	# Enable contact monitoring so body_entered works on RigidBody2D
	contact_monitor = true
	max_contacts_reported = 8
	# Reduce tunneling through walls
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	gravity_scale = 0.0
	linear_damp = 8.0
	angular_damp = 8.0
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
		_clamp_inside_world()
	else:
		# Hard clamp within world tilemap bounds so the can never escapes the fence
		_clamp_inside_world()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Extra safety: clamp position during the physics integration step to fully prevent tunneling
	if is_being_carried:
		return
	var bounds := _get_world_bounds()
	if bounds.is_empty():
		return
	var min_v: Vector2 = bounds["min"]
	var max_v: Vector2 = bounds["max"]
	var pos: Vector2 = state.transform.origin
	var clamped: Vector2 = Vector2(clamp(pos.x, min_v.x, max_v.x), clamp(pos.y, min_v.y, max_v.y))
	if clamped != pos:
		state.transform.origin = clamped
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0

func hit_from(vel: Vector2, hit_pos: Vector2) -> void:
	# Public API for Area2D (slipper) to notify hits
	var impulse := vel * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - hit_pos)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)

func _clamp_inside_world() -> void:
	var bounds := _get_world_bounds()
	if bounds.is_empty():
		return
	var min_v: Vector2 = bounds["min"]
	var max_v: Vector2 = bounds["max"]
	var pos: Vector2 = global_position
	var clamped: Vector2 = Vector2(clamp(pos.x, min_v.x, max_v.x), clamp(pos.y, min_v.y, max_v.y))
	if clamped != pos:
		# Teleport back inside and stop motion to avoid tunneling back out
		freeze = true
		global_position = clamped
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		freeze = false

func _get_world_bounds() -> Dictionary:
	var tilemap := get_tree().get_first_node_in_group("world_tilemap")
	if tilemap == null or not (tilemap is TileMap):
		return {}
	var tm: TileMap = tilemap as TileMap
	var used_rect: Rect2i = tm.get_used_rect()
	var tile_size: Vector2i = tm.tile_set.tile_size
	# Compute bounds in TileMap local space then convert to global
	var left_local: float = float(used_rect.position.x * tile_size.x)
	var top_local: float = float(used_rect.position.y * tile_size.y)
	var right_local: float = float((used_rect.position.x + used_rect.size.x) * tile_size.x)
	var bottom_local: float = float((used_rect.position.y + used_rect.size.y) * tile_size.y)
	var top_left_global: Vector2 = tm.to_global(Vector2(left_local, top_local))
	var bottom_right_global: Vector2 = tm.to_global(Vector2(right_local, bottom_local))
	var left: float = min(top_left_global.x, bottom_right_global.x)
	var top: float = min(top_left_global.y, bottom_right_global.y)
	var right: float = max(top_left_global.x, bottom_right_global.x)
	var bottom: float = max(top_left_global.y, bottom_right_global.y)
	var margin: float = fence_margin
	return {
		"min": Vector2(left + margin, top + margin),
		"max": Vector2(right - margin, bottom - margin)
	}
