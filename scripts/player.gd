extends CharacterBody2D
signal ammo_changed(count: int, max_count: int)
signal slipper_thrown(global_pos: Vector2)
signal returned_to_base()

const SPEED = 100.0
const ACCELERATION = 1500.0
const FRICTION = 1200.0

var current_dir = "none"
@onready var cam: Camera2D = $Camera2D
const RUN_MULTIPLIER := 1.6
const RUN_ACCEL_MULTIPLIER := 1.6
@export var slipper_scene: PackedScene = preload("res://scenes/slipper.tscn")
@export var aim_arrow_scene: PackedScene = preload("res://scenes/aim_arrow.tscn")
var is_throwing: bool = false
var _last_dir_vec: Vector2 = Vector2.DOWN
const MAX_SLIPPERS := 3
var slippers_available: int = MAX_SLIPPERS
var is_hurt: bool = false
var is_aiming: bool = false
var _aim_arrow: Node2D = null
const CHARGE_TIME := 1.0 # seconds to reach max power
const MIN_SPEED_MULT := 0.7
const MAX_SPEED_MULT := 2.0
var _aim_started_at: float = 0.0

# Base zone (green line) logic
@export var base_radius: float = 50.0
var base_center: Vector2
var can_leave_base: bool = false
var at_base: bool = true

func _ready() -> void:
	$AnimatedSprite2D.play("front_idle")
	_setup_camera_limits()
	# tell UI initial ammo
	ammo_changed.emit(slippers_available, MAX_SLIPPERS)
	# initialize base center at spawn
	base_center = global_position
	at_base = true


func _physics_process(delta: float) -> void:
	_update_base_state()
	player_movement(delta)
	# Update aim arrow while aiming
	if is_aiming and _aim_arrow != null:
		var dir := (get_global_mouse_position() - global_position)
		if dir.length() > 0.0 and _aim_arrow.has_method("point_towards"):
			_aim_arrow.point_towards(dir)
		# Update arrow length based on charge power
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		var t: float = clamp((now - _aim_started_at) / CHARGE_TIME, 0.0, 1.0)
		if _aim_arrow.has_method("_set_length"):
			_aim_arrow._set_length(48.0 + 48.0 * t)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Start aiming
			if is_throwing or is_hurt or slippers_available <= 0:
				return
			_start_aim()
		else:
			# Release to throw
			if not is_aiming:
				return
			var dir_vec := (get_global_mouse_position() - global_position).normalized()
			if dir_vec == Vector2.ZERO:
				dir_vec = (_last_dir_vec if _last_dir_vec.length() > 0 else Vector2.DOWN).normalized()
			# Compute power multiplier from hold time
			var now: float = float(Time.get_ticks_msec()) / 1000.0
			var t: float = clamp((now - _aim_started_at) / CHARGE_TIME, 0.0, 1.0)
			var power_mult: float = lerp(MIN_SPEED_MULT, MAX_SPEED_MULT, t)
			_stop_aim()
			_throw_slipper_dir(dir_vec, power_mult)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_recall_nearest_slipper()
	if event.is_action_pressed("recall"):
		_recall_nearest_slipper()

func player_movement(delta):
	# WASD-only controls for Player 1 using physical key codes
	# W(87) A(65) S(83) D(68)
	var input_dir = Vector2()
	if Input.is_physical_key_pressed(87): # W
		input_dir.y -= 1
	if Input.is_physical_key_pressed(83): # S
		input_dir.y += 1
	if Input.is_physical_key_pressed(65): # A
		input_dir.x -= 1
	if Input.is_physical_key_pressed(68): # D
		input_dir.x += 1
	
	# Normalize diagonal movement so it's not faster
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		_last_dir_vec = input_dir

		# Base boundary clamp: if not allowed to leave base, remove outward component at the edge
		if not can_leave_base:
			var to_out := (global_position - base_center)
			var dist := to_out.length()
			if dist > 0.0:
				var outward := to_out / dist
				var outward_comp := input_dir.dot(outward)
				# If at or beyond the boundary and trying to move outward, cancel that component
				if dist >= base_radius - 1.0 and outward_comp > 0.0:
					input_dir = (input_dir - outward * outward_comp).normalized() if (input_dir - outward * outward_comp).length() > 0.001 else Vector2.ZERO

		# Sprint / Run handling (use Shift Right physical if present, otherwise default to false)
		var is_running := Input.is_action_pressed("run")
		var target_speed := SPEED * (RUN_MULTIPLIER if is_running else 1.0)
		var accel := ACCELERATION * (RUN_ACCEL_MULTIPLIER if is_running else 1.0)

		# Smooth acceleration
		velocity = velocity.move_toward(input_dir * target_speed, accel * delta)

		# Speed up animations slightly when running
		$AnimatedSprite2D.speed_scale = 1.2 if is_running else 1.0
		# Update current direction for animations (8 directions)
		current_dir = _dir8_from_vector(input_dir)
		play_anim(1, is_running)
	else:
		# Apply friction when no input
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		$AnimatedSprite2D.speed_scale = 1.0
		play_anim(0, false)
	
	move_and_slide()
	
func play_anim(movement: int, is_running: bool):
	if is_hurt:
		return
	if is_throwing:
		return
	var dir = current_dir
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	
	# Determine base animation name and flip
	var base := "front"  # default
	var use_side := false
	var flip_left := false
	match dir:
		"right":
			base = "side"; use_side = true; flip_left = false
		"left":
			base = "side"; use_side = true; flip_left = true
		"down":
			base = "front"; flip_left = false
		"up":
			base = "back"; flip_left = false
		"down_right":
			base = "front"; flip_left = false
		"down_left":
			base = "front"; flip_left = true
		"up_right":
			base = "back"; flip_left = false
		"up_left":
			base = "back"; flip_left = true

	anim.flip_h = flip_left

	# Build ordered list of candidate animations with smart fallbacks
	var candidates: Array[String] = []
	if movement == 0:
		candidates.append(base + "_idle")
		# Prefer matching family, then try the other vertical family, then front_idle
		if base == "side":
			candidates.append("front_idle")
			candidates.append("back_idle")
		elif base == "front":
			candidates.append("back_idle")
		elif base == "back":
			candidates.append("front_idle")
		candidates.append("front_idle")
	else:
		if is_running:
			candidates.append(base + "_run")
			candidates.append(base + "_walk")
			# If side_* doesn't exist, use front/back run/walk
			if base == "side":
				candidates.append("front_run")
				candidates.append("back_run")
				candidates.append("front_walk")
				candidates.append("back_walk")
			elif base == "front":
				candidates.append("back_run")
				candidates.append("front_walk")
			elif base == "back":
				candidates.append("front_run")
				candidates.append("back_walk")
		else:
			candidates.append(base + "_walk")
			candidates.append(base + "_run")
			if base == "side":
				candidates.append("front_walk")
				candidates.append("back_walk")
				candidates.append("front_run")
				candidates.append("back_run")
			elif base == "front":
				candidates.append("back_walk")
				candidates.append("front_run")
			elif base == "back":
				candidates.append("front_walk")
				candidates.append("back_run")
		# As a last resort, idles
		candidates.append(base + "_idle")
		candidates.append("front_idle")

	# Play first available animation
	var frames: SpriteFrames = anim.sprite_frames
	for name in candidates:
		if frames and frames.has_animation(name):
			anim.play(name)
			return

func play_hurt_from(attacker_global_pos: Vector2) -> void:
	if is_hurt:
		return
	is_hurt = true
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	# Determine whether the hit comes from above (back) or below (front)
	var to_self := global_position - attacker_global_pos
	var base := "front"
	if to_self.y < 0.0:
		base = "back"
	# Flip for left side hits
	anim.flip_h = to_self.x < 0.0
	var candidates: Array[String] = [base + "_hurt", base]
	# Fallbacks to generic idles if hurt clips not found
	candidates.append(base + "_idle")
	candidates.append("front_idle")
	# Play the first available hurt/idle
	var chosen := _choose_first_available(anim, candidates)
	if chosen != "":
		anim.play(chosen)
	# Lock for a short duration or use clip length if non-looping
	var lock_time := 0.35
	var frames := anim.sprite_frames
	if frames and chosen != "":
		var fps := frames.get_animation_speed(chosen)
		var frame_count := frames.get_frame_count(chosen)
		var loops := frames.get_animation_loop(chosen)
		if fps > 0.0 and frame_count > 0 and not loops:
			lock_time = float(frame_count) / fps
	await get_tree().create_timer(lock_time).timeout
	is_hurt = false

func _throw_slipper() -> void:
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	# Aim towards mouse; fallback to last movement dir or down
	var aim := get_global_mouse_position() - global_position
	var dir_vec := aim.normalized()
	if dir_vec == Vector2.ZERO:
		dir_vec = (_last_dir_vec if _last_dir_vec.length() > 0 else Vector2.DOWN).normalized()
	var base := _base_from_vec(dir_vec)
	# Spawn slipper
	if slipper_scene:
		var s = slipper_scene.instantiate()
		if s:
			# Spawn under the player's parent so it shares the same canvas layer
			get_parent().add_child(s)
			s.global_position = global_position + dir_vec.normalized() * 32.0
			if s.has_method("init"):
				s.init(dir_vec)
			if s.has_signal("picked_up"):
				s.connect("picked_up", Callable(self, "_on_slipper_picked"))
			slippers_available = max(0, slippers_available - 1)
			ammo_changed.emit(slippers_available, MAX_SLIPPERS)
			# Notify that we threw a slipper
			slipper_thrown.emit(global_position)
	# Play throw animation with lock and safe fallbacks
	is_throwing = true
	var candidates: Array[String] = [base + "_throw"]
	if base == "side":
		candidates.append("front_throw")
		candidates.append("back_throw")
	else:
		candidates.append("front_throw" if base == "back" else "back_throw")
	candidates.append(base + "_walk")
	candidates.append(base + "_idle")
	candidates.append("front_idle")
	var chosen := _choose_first_available(anim, candidates)
	if chosen != "":
		anim.play(chosen)
	# Determine lock duration
	var lock_time := 0.25
	var frames: SpriteFrames = anim.sprite_frames
	if frames and chosen != "":
		var fps := frames.get_animation_speed(chosen)
		var frame_count := frames.get_frame_count(chosen)
		var loops := frames.get_animation_loop(chosen)
		if fps > 0.0 and frame_count > 0 and not loops:
			lock_time = float(frame_count) / fps
	# Wait for the computed duration
	await get_tree().create_timer(lock_time).timeout
	is_throwing = false

func _on_slipper_picked() -> void:
	slippers_available = min(MAX_SLIPPERS, slippers_available + 1)
	ammo_changed.emit(slippers_available, MAX_SLIPPERS)

func _play_first_available(anim: AnimatedSprite2D, names: Array[String]) -> void:
	var frames: SpriteFrames = anim.sprite_frames
	for n in names:
		if frames and frames.has_animation(n):
			anim.play(n)
			return

func _choose_first_available(anim: AnimatedSprite2D, names: Array[String]) -> String:
	var frames: SpriteFrames = anim.sprite_frames
	for n in names:
		if frames and frames.has_animation(n):
			return n
	return ""

func _throw_slipper_dir(dir_vec: Vector2, power_mult: float = 1.0) -> void:
	# Helper to throw with a precomputed direction vector
	var base := _base_from_vec(dir_vec)
	if slipper_scene:
		var s = slipper_scene.instantiate()
		if s:
			get_parent().add_child(s)
			s.global_position = global_position + dir_vec.normalized() * 32.0
			if s.has_method("init"):
				s.init(dir_vec, power_mult)
			if s.has_signal("picked_up"):
				s.connect("picked_up", Callable(self, "_on_slipper_picked"))
			slippers_available = max(0, slippers_available - 1)
			ammo_changed.emit(slippers_available, MAX_SLIPPERS)
	# Trigger throw animation and lock
	is_throwing = true
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	var candidates: Array[String] = []
	var base_name := ("front" if dir_vec.y >= 0.0 else "back")
	if base_name == "front":
		candidates = ["front_throw", "front_walk", "front_idle"]
	else:
		candidates = ["back_throw", "back_walk", "back_idle", "front_idle"]
	_play_first_available(anim, candidates)
	var frames2: SpriteFrames = anim.sprite_frames
	var chosen2 := _choose_first_available(anim, candidates)
	var lock_time := 0.25
	if frames2 and chosen2 != "":
		var fps := frames2.get_animation_speed(chosen2)
		var frame_count := frames2.get_frame_count(chosen2)
		var loops := frames2.get_animation_loop(chosen2)
		if fps > 0.0 and frame_count > 0 and not loops:
			lock_time = float(frame_count) / fps
	await get_tree().create_timer(lock_time).timeout
	is_throwing = false

func _start_aim() -> void:
	is_aiming = true
	_aim_started_at = float(Time.get_ticks_msec()) / 1000.0
	if aim_arrow_scene and _aim_arrow == null:
		_aim_arrow = aim_arrow_scene.instantiate()
		_aim_arrow.position = Vector2.ZERO
		add_child(_aim_arrow)
		if _aim_arrow.has_method("_set_length"):
			_aim_arrow._set_length(48.0)

func _stop_aim() -> void:
	is_aiming = false
	if _aim_arrow != null:
		_aim_arrow.queue_free()
		_aim_arrow = null

func _recall_nearest_slipper() -> void:
	# Find the closest active slipper in the scene and trigger its recall behavior
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var best: Node2D = null
	var best_d2: float = INF
	for n in root.get_tree().get_nodes_in_group("slipper"):
		if n is Node2D and n.is_inside_tree():
			var sn: Node2D = n as Node2D
			var d2: float = (sn.global_position - global_position).length_squared()
			if d2 < best_d2:
				best = sn
				best_d2 = d2
	if best and best.has_method("begin_recall"):
		best.begin_recall()

func _base_from_dir(dir: String) -> String:
	match dir:
		"right", "left":
			return "side"
		"up", "up_right", "up_left":
			return "back"
		_:
			return "front"

func _base_from_vec(v: Vector2) -> String:
	if abs(v.x) > abs(v.y):
		return "side"
	elif v.y < 0:
		return "back"
	else:
		return "front"

func _vector_from_dir8(dir: String) -> Vector2:
	match dir:
		"right": return Vector2.RIGHT
		"down_right": return Vector2(1, 1).normalized()
		"down": return Vector2.DOWN
		"down_left": return Vector2(-1, 1).normalized()
		"left": return Vector2.LEFT
		"up_left": return Vector2(-1, -1).normalized()
		"up": return Vector2.UP
		"up_right": return Vector2(1, -1).normalized()
		_: return Vector2.ZERO

func _dir8_from_vector(v: Vector2) -> String:
	# Returns one of: up, up_right, right, down_right, down, down_left, left, up_left
	# Use degrees and modulo for robust sector mapping
	var angle_deg: float = rad_to_deg(atan2(v.y, v.x)) # right=0, down=+90
	if angle_deg < 0:
		angle_deg += 360.0
	var sector := int(floor((angle_deg + 22.5) / 45.0)) % 8
	match sector:
		0: return "right"
		1: return "down_right"
		2: return "down"
		3: return "down_left"
		4: return "left"
		5: return "up_left"
		6: return "up"
		7: return "up_right"
		_: return "down"

func _setup_camera_limits() -> void:
	# Try to find a TileMap with the group "world_tilemap" to set camera limits
	if cam == null:
		return
	var tilemap := get_tree().get_first_node_in_group("world_tilemap")
	# Fallback: search the current scene for any TileMap if group is missing
	if tilemap == null:
		var root := get_tree().current_scene
		if root:
			for child in root.get_children():
				if child is TileMap:
					tilemap = child
					break
	if tilemap == null:
		return
	# Compute pixel bounds from the used Rect and tile size
	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2i = tilemap.tile_set.tile_size
	var left = used_rect.position.x * tile_size.x
	var top = used_rect.position.y * tile_size.y
	var right = (used_rect.position.x + used_rect.size.x) * tile_size.x
	var bottom = (used_rect.position.y + used_rect.size.y) * tile_size.y

	cam.limit_left = left
	cam.limit_top = top
	cam.limit_right = right
	cam.limit_bottom = bottom
	cam.enabled = true
	cam.make_current()

# Base-state helpers
func _update_base_state() -> void:
	# Determine if any active slipper is currently outside the base radius
	var slipper_outside := false
	for n in get_tree().get_nodes_in_group("slipper"):
		if n is Node2D and n.is_inside_tree():
			var d: float = (n.global_position - base_center).length()
			if d > base_radius + 1.0:
				slipper_outside = true
				break
	can_leave_base = slipper_outside

	var was_at_base := at_base
	at_base = (global_position.distance_to(base_center) <= base_radius + 0.5)
	# If we just re-entered base and no slipper is outside, re-lock and emit
	if at_base and not was_at_base and not can_leave_base:
		returned_to_base.emit()
