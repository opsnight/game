extends CharacterBody2D

# --- Sync properties replicated by MultiplayerSynchronizer ---
@export var sync_position: Vector2
@export var sync_velocity: Vector2
@export var sync_animation: String = "front_idle"
@export var sync_flip_h: bool = false

var is_local_player: bool = false
var _anim: AnimatedSprite2D
var _camera: Camera2D

@export var role: String = "thrower" : set = set_role # "defender" | "thrower" | "spectator"

const SPEED := 100.0
const ACCELERATION := 1500.0
const FRICTION := 1200.0

var _last_dir_vec: Vector2 = Vector2.DOWN

# Throwing (for thrower role)
signal ammo_changed(count: int, max_count: int)
@export var aim_arrow_scene: PackedScene = preload("res://scenes/aim_arrow.tscn")
const MAX_SLIPPERS := 1
var slippers_available: int = MAX_SLIPPERS
var is_aiming: bool = false
var _aim_arrow: Node2D = null
const CHARGE_TIME := 1.0
const MIN_SPEED_MULT := 0.7
const MAX_SPEED_MULT := 2.0
var _aim_started_at: float = 0.0

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
	_apply_role_visual()
	_setup_multiplayer_sync()
	_update_local_authority_state()
	_update_local_cameras()
	# Initialize HUD ammo for local player
	if is_local_player:
		ammo_changed.emit(slippers_available, MAX_SLIPPERS)

func set_role(v: String) -> void:
	role = v
	_apply_role_visual()

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
		_setup_camera_limits()
		_camera.enabled = true
		_camera.make_current()
	else:
		_camera.enabled = false

func _setup_camera_limits() -> void:
	if _camera == null:
		return
	var tilemap := get_tree().get_first_node_in_group("world_tilemap")
	if tilemap == null:
		var root := get_tree().current_scene
		if root:
			for child in root.get_children():
				if child is TileMap:
					tilemap = child
					break
	if tilemap == null:
		return
	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2i = tilemap.tile_set.tile_size
	var left = used_rect.position.x * tile_size.x
	var top = used_rect.position.y * tile_size.y
	var right = (used_rect.position.x + used_rect.size.x) * tile_size.x
	var bottom = (used_rect.position.y + used_rect.size.y) * tile_size.y
	_camera.limit_left = left
	_camera.limit_top = top
	_camera.limit_right = right
	_camera.limit_bottom = bottom

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

	# Role-specific actions (local only)
	if role.to_lower() == "thrower":
		_handle_thrower_input()
	elif role.to_lower() == "defender":
		_handle_defender_input()

func _handle_thrower_input() -> void:
	# Use _unhandled_input-like polling for mouse button states to avoid focus issues
	# Start aim on press
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not is_aiming and slippers_available > 0:
			is_aiming = true
			_aim_started_at = float(Time.get_ticks_msec()) / 1000.0
			if aim_arrow_scene and _aim_arrow == null:
				_aim_arrow = aim_arrow_scene.instantiate()
				_aim_arrow.position = Vector2.ZERO
				add_child(_aim_arrow)
				if _aim_arrow.has_method("_set_length"):
					_aim_arrow._set_length(48.0)
	else:
		# Release to throw
		if is_aiming:
			var dir_vec := (get_global_mouse_position() - global_position).normalized()
			if dir_vec == Vector2.ZERO:
				dir_vec = (_last_dir_vec if _last_dir_vec.length() > 0 else Vector2.DOWN).normalized()
			var now: float = float(Time.get_ticks_msec()) / 1000.0
			var t: float = clamp((now - _aim_started_at) / CHARGE_TIME, 0.0, 1.0)
			var power_mult: float = lerp(MIN_SPEED_MULT, MAX_SPEED_MULT, t)
			_stop_aim()
			_throw_network_slipper(dir_vec, power_mult)

	# Update arrow while aiming
	if is_aiming and _aim_arrow != null:
		var dir := (get_global_mouse_position() - global_position)
		if dir.length() > 0.0 and _aim_arrow.has_method("point_towards"):
			_aim_arrow.point_towards(dir)
		var now2: float = float(Time.get_ticks_msec()) / 1000.0
		var t2: float = clamp((now2 - _aim_started_at) / CHARGE_TIME, 0.0, 1.0)
		if _aim_arrow.has_method("_set_length"):
			_aim_arrow._set_length(48.0 + 48.0 * t2)

func _stop_aim() -> void:
	is_aiming = false
	if _aim_arrow != null:
		_aim_arrow.queue_free()
		_aim_arrow = null

func _throw_network_slipper(dir_vec: Vector2, power_mult: float) -> void:
	if slippers_available <= 0:
		return
	var world := get_tree().current_scene
	if world and world.has_method("_rpc_spawn_slipper"):
		var spawn_pos := global_position + dir_vec.normalized() * 32.0
		world.rpc("_rpc_spawn_slipper", spawn_pos, dir_vec, power_mult, multiplayer.get_unique_id())
		slippers_available = max(0, slippers_available - 1)
		ammo_changed.emit(slippers_available, MAX_SLIPPERS)

func _handle_defender_input() -> void:
	# Optional: Press Numpad 0 to print punch action (placeholder for network catch)
	if Input.is_key_pressed(KEY_KP_0):
		# Placeholder punch window - could add area checks or RPC later
		pass

func _apply_role_visual() -> void:
	# Simple tint based on role to identify in-game quickly
	if _anim == null:
		return
	match role.to_lower():
		"defender":
			_anim.self_modulate = Color(1.0, 0.7, 0.7, 1.0) # reddish
		"spectator":
			_anim.self_modulate = Color(0.75, 0.75, 0.75, 1.0) # gray
		_:
			_anim.self_modulate = Color(1,1,1,1)

@rpc("any_peer", "call_local", "reliable")
func _rpc_gain_ammo() -> void:
	slippers_available = min(MAX_SLIPPERS, slippers_available + 1)
	ammo_changed.emit(slippers_available, MAX_SLIPPERS)

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_ammo(count: int) -> void:
	slippers_available = clamp(count, 0, MAX_SLIPPERS)
	ammo_changed.emit(slippers_available, MAX_SLIPPERS)

func _on_slipper_picked_server() -> void:
	# Server tells the owning client to restore ammo
	rpc_id(get_multiplayer_authority(), "_rpc_gain_ammo")

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
	var p_role := NodePath(".:role")
	rc.add_property(p_pos)
	rc.add_property(p_vel)
	rc.add_property(p_anim)
	rc.add_property(p_flip)
	rc.add_property(p_role)
	rc.property_set_replication_mode(p_pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	rc.property_set_replication_mode(p_vel, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	rc.property_set_replication_mode(p_anim, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	rc.property_set_replication_mode(p_flip, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	rc.property_set_replication_mode(p_role, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	rc.property_set_spawn(p_pos, true)
	rc.property_set_spawn(p_vel, true)
	rc.property_set_spawn(p_anim, true)
	rc.property_set_spawn(p_flip, true)
	rc.property_set_spawn(p_role, true)
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
