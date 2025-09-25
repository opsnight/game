extends RigidBody2D

signal picked_up
signal ai_picked_up

# Throw parameters (top-down, so no gravity)
@export var speed: float = 800.0
@export var linear_damp_when_free: float = 4.0
@export var angular_spin: float = 6.0
@export var pickup_radius: float = 24.0
@export var ground_threshold: float = 50.0  # Speed below which slipper is considered "on ground"

@onready var pickup_area: Area2D = get_node_or_null("PickupArea")
var is_thrown: bool = true
var on_ground: bool = false

@export var sync_position: Vector2
@export var sync_linear_velocity: Vector2
@export var sync_rotation: float = 0.0

func _ready() -> void:
	if not is_in_group("slipper"):
		add_to_group("slipper")
	# Enable contact monitoring so we can detect overlaps for pickup and cans
	contact_monitor = true
	max_contacts_reported = 8
	# Connect to body_entered if available
	if has_signal("body_entered"):
		connect("body_entered", Callable(self, "_on_body_entered"))
	# Setup pickup area for reliable player contact detection
	if pickup_area:
		pickup_area.body_entered.connect(Callable(self, "_on_pickup_body_entered"))
		# Ensure the area can detect most bodies regardless of project layers
		pickup_area.collision_mask = 0x7FFFFFFF
	# No gravity in top-down
	gravity_scale = 0.0
	# Let the body slow down naturally
	linear_damp = linear_damp_when_free
	angular_damp = 1.5

	# Setup replication config if a MultiplayerSynchronizer child exists
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		var rc := SceneReplicationConfig.new()
		var p_pos := NodePath(".:sync_position")
		var p_lin := NodePath(".:sync_linear_velocity")
		var p_rot := NodePath(".:sync_rotation")
		rc.add_property(p_pos)
		rc.add_property(p_lin)
		rc.add_property(p_rot)
		rc.property_set_replication_mode(p_pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		rc.property_set_replication_mode(p_lin, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		rc.property_set_replication_mode(p_rot, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		rc.property_set_spawn(p_pos, true)
		rc.property_set_spawn(p_lin, true)
		rc.property_set_spawn(p_rot, true)
		sync.replication_config = rc
		sync_position = global_position
		sync_linear_velocity = linear_velocity
		sync_rotation = rotation

func init(dir: Vector2, power: float = 1.0) -> void:
	# Initialize throw direction and set physics velocities
	var d: Vector2 = dir
	if d.length() == 0:
		d = Vector2.DOWN
	var p: float = max(0.05, power)
	linear_velocity = d.normalized() * speed * p
	# Give a little spin for visual appeal
	angular_velocity = sign(d.x) * angular_spin
	rotation = linear_velocity.angle()

func _physics_process(delta: float) -> void:
	# Check if slipper has slowed down enough to be considered "on ground"
	var current_speed = linear_velocity.length()
	if is_thrown and current_speed < ground_threshold:
		on_ground = true
		is_thrown = false

	# Align sprite to travel direction when moving
	if current_speed > 1.0:
		rotation = linear_velocity.angle()

	# Server writes state, clients follow
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		if multiplayer.is_server():
			sync_position = global_position
			sync_linear_velocity = linear_velocity
			sync_rotation = rotation
		else:
			var alpha: float = clamp(delta * 10.0, 0.0, 1.0)
			global_position = global_position.lerp(sync_position, alpha)
			linear_velocity = linear_velocity.lerp(sync_linear_velocity, alpha)
			rotation = lerp_angle(rotation, sync_rotation, alpha)

func _on_body_entered(body: Node) -> void:
	# If we hit a can, let physics handle the impulse. Optionally notify the can.
	if body and body.is_in_group("can"):
		if body.has_method("hit_from"):
			body.hit_from(linear_velocity, global_position)
		# Do NOT free the slipper; it should remain in the scene to be retrieved
		return

func _on_pickup_body_entered(body: Node) -> void:
	# Only allow pickup when slipper is on ground
	if not on_ground:
		return
		
	# Dedicated handler for the PickupArea -> only pick up when player overlaps the area
	if body is CharacterBody2D and ("player" in String(body.name).to_lower() or body.has_method("_on_slipper_picked")):
		# Only the server should decide pickup to avoid divergence
		if multiplayer.is_server():
			emit_signal("picked_up")
			queue_free()

func is_on_ground() -> bool:
	return on_ground
func ai_pickup() -> void:
	# Only the server should decide pickup to avoid divergence
	if multiplayer.is_server():
		emit_signal("ai_picked_up")
		queue_free()
