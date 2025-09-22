extends RigidBody2D

@export var hit_impulse_scale: float = 1.2
@export var min_impulse: float = 150.0

# Remember original spawn to allow resets and knockdown checks
var original_position: Vector2
var is_being_carried: bool = false
var carrier: Node2D = null

func _ready() -> void:
	# Enable contact monitoring so body_entered works on RigidBody2D
	contact_monitor = true
	max_contacts_reported = 8
	gravity_scale = 0.0
	linear_damp = 6.0
	angular_damp = 6.0
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

func hit_from(vel: Vector2, hit_pos: Vector2) -> void:
	# Public API for Area2D (slipper) to notify hits
	var impulse := vel * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - hit_pos)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)
