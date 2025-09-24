extends CharacterBody2D

# --- Sync properties replicated by MultiplayerSynchronizer ---
@export var sync_position: Vector2
@export var sync_velocity: Vector2
@export var sync_animation: String = "front_idle"
@export var sync_flip_h: bool = false

var is_local_player: bool = false
var _anim: AnimatedSprite2D
var _camera: Camera2D

const SPEED := 100.0
const ACCELERATION := 1500.0
const FRICTION := 1200.0

var _last_dir_vec: Vector2 = Vector2.DOWN

func _ready() -> void:
	_anim = $AnimatedSprite2D
	_camera = get_node_or_null("Camera2D")
	if _anim:
		_anim.play("front_idle")
		# Ensure this character always draws above the TileMap
		self.z_as_relative = false
		self.z_index = 200
		_anim.z_index = 200
		_anim.visible = true
	_setup_multiplayer_sync()
	_update_local_authority_state()
	_update_local_cameras()

func _physics_process(delta: float) -> void:
	# Keep authority detection updated (handles network timing cases)
	_update_local_authority_state()
	_update_local_cameras()
	if is_local_player:
		_handle_input(delta)
		_update_sync_properties()
	else:
		_apply_sync_properties()
	move_and_slide()

# --- Multiplayer / Authority helpers ---
func _update_local_authority_state() -> void:
	var current_authority := get_multiplayer_authority()
	var local_peer_id := multiplayer.get_unique_id()
	var should_be_local := (current_authority == local_peer_id)
	if is_local_player != should_be_local:
		is_local_player = should_be_local

func _update_local_cameras() -> void:
	if _camera == null:
		return
	# Only the local player should have an active camera and make it current
	if is_local_player:
		_camera.enabled = true
		_camera.make_current()
	else:
		_camera.enabled = false

# --- Input & Anim ---
func _handle_input(delta: float) -> void:
	var input_dir := Vector2.ZERO
	# For simplicity, let each peer use WASD (per-machine input)
	if Input.is_physical_key_pressed(87): # W
		input_dir.y -= 1
	if Input.is_physical_key_pressed(83): # S
		input_dir.y += 1
	if Input.is_physical_key_pressed(65): # A
		input_dir.x -= 1
	if Input.is_physical_key_pressed(68): # D
		input_dir.x += 1
	if input_dir.length() > 0.0:
		_last_dir_vec = input_dir.normalized()
		var is_running: bool = Input.is_action_pressed("run")
		var target_speed: float = SPEED * (1.6 if is_running else 1.0)
		var accel: float = ACCELERATION * (1.6 if is_running else 1.0)
		velocity = velocity.move_toward(_last_dir_vec * target_speed, accel * delta)
		if _anim:
			_anim.speed_scale = 1.3 if is_running else 1.0
		_play_anim_state(true, is_running)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		if _anim:
			_anim.speed_scale = 1.0
		_play_anim_state(false, false)

func _play_anim_state(is_moving: bool, is_running: bool) -> void:
	if _anim == null:
		return
	# Flip horizontally by X direction
	_anim.flip_h = (velocity.x < 0.0)
	var desired := "front_idle"
	if abs(_last_dir_vec.y) > abs(_last_dir_vec.x):
		if _last_dir_vec.y < 0.0:
			desired = ("back_run" if is_running else ("back_walk" if is_moving else "back_idle"))
		else:
			desired = ("front_run" if is_running else ("front_walk" if is_moving else "front_idle"))
	else:
		desired = ("front_run" if is_running else ("front_walk" if is_moving else "front_idle"))
	var frames := _anim.sprite_frames
	if frames:
		if not frames.has_animation(desired):
			# Fallback to walk if run animations are not present in this scene
			if desired == "front_run":
				desired = "front_walk"
			elif desired == "back_run":
				desired = "back_walk"
		if frames.has_animation(desired) and _anim.animation != desired:
			_anim.play(desired)

# --- Synchronization ---
func _setup_multiplayer_sync() -> void:
	var sync_node: MultiplayerSynchronizer = $MultiplayerSynchronizer
	if sync_node == null:
		return
	var rc := SceneReplicationConfig.new()
	var p_pos := NodePath(".:sync_position")
	var p_vel := NodePath(".:sync_velocity")
	var p_anim := NodePath(".:sync_animation")
	var p_flip := NodePath(".:sync_flip_h")
	rc.add_property(p_pos)
	rc.add_property(p_vel)
	rc.add_property(p_anim)
	rc.add_property(p_flip)
	rc.property_set_replication_mode(p_pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	rc.property_set_replication_mode(p_vel, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	rc.property_set_replication_mode(p_anim, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	rc.property_set_replication_mode(p_flip, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	rc.property_set_spawn(p_pos, true)
	rc.property_set_spawn(p_vel, true)
	rc.property_set_spawn(p_anim, true)
	rc.property_set_spawn(p_flip, true)
	sync_node.replication_config = rc

func _update_sync_properties() -> void:
	sync_position = global_position
	sync_velocity = velocity
	if _anim:
		sync_animation = _anim.animation
		sync_flip_h = _anim.flip_h

func _apply_sync_properties() -> void:
	# Interpolate position for smoothness
	global_position = global_position.lerp(sync_position, 0.12)
	velocity = sync_velocity
	if _anim:
		if _anim.animation != sync_animation and _anim.sprite_frames and _anim.sprite_frames.has_animation(sync_animation):
			_anim.play(sync_animation)
		_anim.flip_h = sync_flip_h
