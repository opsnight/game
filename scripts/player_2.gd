extends CharacterBody2D

signal caught_player

const SPEED: float = 100.0
const ACCELERATION: float = 1500.0
const FRICTION: float = 1200.0
const RUN_MULTIPLIER: float = 1.6
const RUN_ACCEL_MULTIPLIER: float = 1.6

var current_dir: String = "down"
var is_attacking: bool = false
@export var catch_radius: float = 28.0

func _ready() -> void:
	$AnimatedSprite2D.play("f_idle")

func _physics_process(delta: float) -> void:
	player_movement(delta)
	if is_attacking:
		_try_catch()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_attack()
	elif event.is_action_pressed("attack"):
		_start_attack()

func player_movement(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("right"):
		input_dir.x += 1
	if Input.is_action_pressed("left"):
		input_dir.x -= 1
	if Input.is_action_pressed("down"):
		input_dir.y += 1
	if Input.is_action_pressed("up"):
		input_dir.y -= 1

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		var is_running: bool = Input.is_action_pressed("run")
		var target_speed: float = SPEED * (RUN_MULTIPLIER if is_running else 1.0)
		var accel: float = ACCELERATION * (RUN_ACCEL_MULTIPLIER if is_running else 1.0)
		velocity = velocity.move_toward(input_dir * target_speed, accel * delta)
		$AnimatedSprite2D.speed_scale = 1.2 if is_running else 1.0
		current_dir = _dir8_from_vector(input_dir)
		_play_anim(1, is_running)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		$AnimatedSprite2D.speed_scale = 1.0
		_play_anim(0, false)

	move_and_slide()

func _play_anim(movement: int, is_running: bool) -> void:
	if is_attacking:
		return
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	var base: String = _base_from_dir(current_dir) # "f" or "b"
	var flip_left: bool = current_dir in ["left", "down_left", "up_left"]
	anim.flip_h = flip_left

	var candidates: Array[String] = []
	if movement == 0:
		candidates.append(base + "_idle")
		candidates.append(("b_idle" if base == "f" else "f_idle"))
		candidates.append("f_idle")
	else:
		if is_running:
			candidates.append(base + "_run")
			candidates.append(base + "_walk")
			candidates.append(("b_run" if base == "f" else "f_run"))
			candidates.append(("b_walk" if base == "f" else "f_walk"))
		else:
			candidates.append(base + "_walk")
			candidates.append(base + "_run")
			candidates.append(("b_walk" if base == "f" else "f_walk"))
			candidates.append(("b_run" if base == "f" else "f_run"))
		candidates.append(base + "_idle")
		candidates.append("f_idle")

	var frames: SpriteFrames = anim.sprite_frames
	for name in candidates:
		if frames and frames.has_animation(name):
			anim.play(name)
			return

func _start_attack() -> void:
	if is_attacking:
		return
	is_attacking = true
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	var base: String = _base_from_dir(current_dir)
	var flip_left: bool = current_dir in ["left", "down_left", "up_left"]
	anim.flip_h = flip_left
	var name: String = base + "_attack" # expects f_attack or b_attack
	var played: bool = false
	if anim.sprite_frames and anim.sprite_frames.has_animation(name):
		anim.play(name)
		played = true
	else:
		# Fallback to idle if attack anim not present
		anim.play(base + "_idle")
	# Compute attack window from frames if possible
	var lock_time: float = 0.35
	if played:
		var fps: float = anim.sprite_frames.get_animation_speed(name)
		var frames_count: int = anim.sprite_frames.get_frame_count(name)
		var loops: bool = anim.sprite_frames.get_animation_loop(name)
		if fps > 0 and frames_count > 0 and not loops:
			lock_time = float(frames_count) / fps
	await get_tree().create_timer(lock_time).timeout
	is_attacking = false

func _try_catch() -> void:
	# Find main player and check proximity
	var player: Node = get_tree().current_scene.find_child("player", true, false)
	if player and player is CharacterBody2D:
		if global_position.distance_to(player.global_position) <= catch_radius:
			emit_signal("caught_player")
			if player.has_method("play_hurt_from"):
				player.play_hurt_from(global_position)

func _base_from_dir(dir: String) -> String:
	match dir:
		"up", "up_right", "up_left":
			return "b"
		_:
			return "f"

func _dir8_from_vector(v: Vector2) -> String:
	var angle_deg: float = rad_to_deg(atan2(v.y, v.x))
	if angle_deg < 0.0:
		angle_deg += 360.0
	var sector: int = int(floor((angle_deg + 22.5) / 45.0)) % 8
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
