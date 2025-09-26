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

# Rotation state tracking
var last_pre_hit_rotation: float = 0.0
var _score_pending: bool = false

@export var sync_position: Vector2
@export var sync_linear_velocity: Vector2
@export var sync_rotation: float = 0.0

func _ready() -> void:
	# Enable contact monitoring so body_entered works on RigidBody2D
	contact_monitor = true
	max_contacts_reported = 8
	# Reduce tunneling through walls
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	linear_damp = 3.0
	angular_damp = 3.0
	# Top-down game: disable gravity so the can doesn't fall "down"
	gravity_scale = 0.0
	# Help prevent tunneling on hard hits
	set_deferred("continuous_cd", true)
	if not is_in_group("can"):
		add_to_group("can")
	self.body_entered.connect(Callable(self, "_on_body_entered"))
	# Store original spawn
	original_position = global_position
	last_pre_hit_rotation = rotation
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
		# Initialize sync properties only in networked sessions
		if _is_networked():
			sync_position = global_position
			sync_linear_velocity = linear_velocity
			sync_rotation = rotation

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("slipper"):
		_apply_hit_from(body)

func _apply_hit_from(node: Node) -> void:
	# Remember rotation just before applying the hit impulse
	last_pre_hit_rotation = rotation
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
	# Ensure the body moves and doesn't stay sleeping
	sleeping = false
	# Briefly reduce damping so light hits still produce visible motion
	_call_temporal_motion_boost()
	# Schedule scoring after motion begins
	if not _score_pending:
		_score_pending = true
		call_deferred("_score_when_settled")

func is_knocked_down(threshold: float = 30.0) -> bool:
	# Consider knocked down if moved sufficiently from original position
	return global_position.distance_to(original_position) > threshold

func begin_carry(by: Node2D) -> void:
	# Freeze physics and attach visually to the carrier
	is_being_carried = true
	carrier = by
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
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync and _is_networked():
		var is_authority := multiplayer.is_server()
		if is_authority:
			sync_position = global_position
			sync_linear_velocity = linear_velocity
			sync_rotation = rotation
		else:
			var alpha: float = clamp(delta * 8.0, 0.0, 1.0)
			global_position = global_position.lerp(sync_position, alpha)
			linear_velocity = linear_velocity.lerp(sync_linear_velocity, alpha)
			rotation = lerp_angle(rotation, sync_rotation, alpha)
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
	# Remember rotation just before applying the hit impulse
	last_pre_hit_rotation = rotation
	var impulse := vel * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - hit_pos)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)
	sleeping = false
	_call_temporal_motion_boost()
	if not _score_pending:
		_score_pending = true
		call_deferred("_score_when_settled")

func _call_temporal_motion_boost() -> void:
	# Temporarily lower damp to allow more visible sliding/rolling, restore after
	var old_lin := linear_damp
	var old_ang := angular_damp
	linear_damp = max(1.0, old_lin * 0.5)
	angular_damp = max(1.0, old_ang * 0.5)
	await get_tree().create_timer(0.35).timeout
	linear_damp = old_lin
	angular_damp = old_ang
	
	# (Scoring moved to _score_when_settled based on displacement)
	var defender = get_tree().get_first_node_in_group("defender")
	if defender and defender.has_method("on_can_hit"):
		defender.on_can_hit()

func restore() -> void:
	# Reset can to upright position and stop movement
	rotation = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	# Do not auto-teleport to original position here; defender should carry it back

func restore_lying() -> void:
	# Keep current rotation (likely lying), just stop motion
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	sleeping = false

func restore_with_pre_hit_rotation() -> void:
	# Restore to the rotation saved immediately before the last hit
	rotation = last_pre_hit_rotation
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	sleeping = false

func reset_to_original() -> void:
	# Hard reset to initial spawn (used by defender when returning can)
	global_position = original_position
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	sleeping = false

func _score_when_settled() -> void:
	# Wait until the can slows down, then award score based on displacement
	var settle_threshold: float = 22.0
	var wait_time: float = 0.0
	var max_wait: float = 1.5
	while wait_time < max_wait and linear_velocity.length() > settle_threshold:
		await get_tree().create_timer(0.08).timeout
		wait_time += 0.08
	# Compute distance from original position
	var dist: float = global_position.distance_to(original_position)
	# Map distance to points: 5 min, 100 max, ~1 pt per 12 px
	var points: int = int(clamp(round(dist / 12.0), 5.0, 100.0))
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("add_score"):
		game_manager.add_score(points)
	_score_pending = false

func _is_networked() -> bool:
	var mp := get_tree().get_multiplayer()
	return mp != null and mp.multiplayer_peer != null
