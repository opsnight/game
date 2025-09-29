extends RigidBody2D

signal picked_up
signal ai_picked_up

# Throw parameters (top-down, so no gravity)
@export var speed: float = 800.0
@export var linear_damp_when_free: float = 4.0
@export var angular_spin: float = 6.0
@export var pickup_radius: float = 40.0
@export var ground_threshold: float = 50.0  # Speed below which slipper is considered "on ground"
@export var pickup_cooldown: float = 0.0  # Seconds after throw before pickup allowed (0 = instant)

@onready var pickup_area: Area2D = get_node_or_null("PickupArea")
var is_thrown: bool = true
var on_ground: bool = false
var _spawn_time_s: float = 0.0

@export var sync_position: Vector2
@export var sync_linear_velocity: Vector2
@export var sync_rotation: float = 0.0

# World bounds helpers
var _tilemap: TileMap = null
var _bounds_inset: float = 10.0

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
		pickup_area.monitoring = true
		# Ensure the pickup circle has a proper radius
		var pc: CollisionShape2D = pickup_area.get_node_or_null("PickupCollision")
		if pc:
			if pc.shape == null:
				var circ := CircleShape2D.new()
				circ.radius = pickup_radius
				pc.shape = circ
			elif pc.shape is CircleShape2D:
				(pc.shape as CircleShape2D).radius = pickup_radius
	# No gravity in top-down
	gravity_scale = 0.0
	# Reduce tunneling through walls/objects
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	set_deferred("continuous_cd", true)
	# Let the body slow down naturally
	linear_damp = linear_damp_when_free
	angular_damp = 1.5

	# Gentle ricochet off walls if they have collision shapes
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25
	mat.friction = 0.9
	physics_material_override = mat
	# Mark spawn time for pickup cooldown
	_spawn_time_s = float(Time.get_ticks_msec()) / 1000.0

	# Cache tilemap for bounds clamping (group should be set by world scene)
	_tilemap = get_tree().get_first_node_in_group("world_tilemap")

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
		# Defer initial sync snapshot until after parent sets transform (only when networked)
		if _is_networked():
			call_deferred("_init_sync_snapshot")

func _init_sync_snapshot() -> void:
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync_position = global_position
		sync_linear_velocity = linear_velocity
		sync_rotation = rotation

func _is_networked() -> bool:
	var mp := get_tree().get_multiplayer()
	return mp != null and mp.multiplayer_peer != null

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
	# Nudge slightly forward to avoid overlapping the thrower collider
	global_position += dir.normalized() * 2.0

func ignore_body_temporarily(body: Node, seconds: float = 0.25) -> void:
	if body == null:
		return
	if has_method("add_collision_exception_with"):
		add_collision_exception_with(body)
		var t := get_tree().create_timer(max(0.01, seconds))
		await t.timeout
		if is_inside_tree() and has_method("remove_collision_exception_with"):
			remove_collision_exception_with(body)

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
	if sync and _is_networked():
		if multiplayer.is_server():
			sync_position = global_position
			sync_linear_velocity = linear_velocity
			sync_rotation = rotation
		else:
			var alpha: float = clamp(delta * 10.0, 0.0, 1.0)
			global_position = global_position.lerp(sync_position, alpha)
			linear_velocity = linear_velocity.lerp(sync_linear_velocity, alpha)
			rotation = lerp_angle(rotation, sync_rotation, alpha)

	# Clamp inside world bounds if available
	_clamp_inside_bounds()

	# Manual grab: do not auto-pickup via polling; handled by server RPC in world.gd

func _on_body_entered(body: Node) -> void:
	# If we hit a can, let physics handle the impulse. Optionally notify the can.
	if body and body.is_in_group("can"):
		if body.has_method("hit_from"):
			body.hit_from(linear_velocity, global_position)
		# Do NOT free the slipper; it should remain in the scene to be retrieved
		return

func _on_pickup_body_entered(body: Node) -> void:
	# Manual grab required now; this callback no longer auto-picks up the slipper.
	# Kept for future UI prompts when a player is in range.
	pass

func _is_valid_player_body(body: Node) -> bool:
	if body is CharacterBody2D:
		var nm := String(body.name).to_lower()
		if nm.find("player") != -1:
			return true
		# Support named networked players and possible future tags
		if body.has_method("_on_slipper_picked"):
			return true
	return false

func is_on_ground() -> bool:
	return on_ground
func ai_pickup() -> void:
	# Only the server should decide pickup to avoid divergence
	if multiplayer.is_server():
		emit_signal("ai_picked_up")
		queue_free()

func _clamp_inside_bounds() -> void:
	if _tilemap == null:
		# Try to resolve lazily
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
	# Work in TileMap local space
	var local_pos: Vector2 = (_tilemap.to_local(global_position))
	var clamped := Vector2(clamp(local_pos.x, left, right), clamp(local_pos.y, top, bottom))
	if clamped != local_pos:
		global_position = _tilemap.to_global(clamped)
