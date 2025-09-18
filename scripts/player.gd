extends CharacterBody2D

signal ammo_changed(count: int, max_count: int)

const SPEED = 100.0
const ACCELERATION = 1500.0
const FRICTION = 1200.0

var current_dir = "none"
@onready var cam: Camera2D = $Camera2D
const RUN_MULTIPLIER := 1.6
const RUN_ACCEL_MULTIPLIER := 1.6
@export var slipper_scene: PackedScene = preload("res://scenes/slipper.tscn")
var is_throwing: bool = false
var _last_dir_vec: Vector2 = Vector2.DOWN
const MAX_SLIPPERS := 3
var slippers_available: int = MAX_SLIPPERS

func _ready() -> void:
	$AnimatedSprite2D.play("front_idle")
	_setup_camera_limits()
	# tell UI initial ammo
	ammo_changed.emit(slippers_available, MAX_SLIPPERS)


func _physics_process(delta: float) -> void:
	player_movement(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_throwing:
			return
		if slippers_available <= 0:
			return
		_throw_slipper()

func player_movement(delta):
	# Get input direction
	var input_dir = Vector2()
	
	if Input.is_action_pressed("right"):
		input_dir.x += 1
	if Input.is_action_pressed("left"):
		input_dir.x -= 1
	if Input.is_action_pressed("down"):
		input_dir.y += 1
	if Input.is_action_pressed("up"):
		input_dir.y -= 1
	
	# Normalize diagonal movement so it's not faster
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		_last_dir_vec = input_dir

		# Sprint / Run handling
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
