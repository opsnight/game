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

# References and state
var can_node: Node2D = null
var player1: Node = null
var can_chase_player: bool = false
var carry_pickup_radius: float = 36.0
var carry_drop_radius: float = 24.0

func _ready() -> void:
	# Ensure sprite renders above the TileMap
	self.z_index = 100
	$AnimatedSprite2D.z_index = 100
	$AnimatedSprite2D.play("f_idle")
	# Cache references
	player1 = get_tree().current_scene.find_child("player", true, false)
	var found_can := get_tree().current_scene.find_child("Can", true, false)
	if found_can and found_can is Node2D:
		can_node = found_can

func _physics_process(delta: float) -> void:
	player_movement(delta)
	# Interactions: catch and can handling
	if can_chase_player:
		_try_catch()
	_handle_can_interactions()

func _unhandled_input(event: InputEvent) -> void:
	pass

func player_movement(delta: float) -> void:
	# Arrow keys only using physical key codes
	# Left(4194319) Right(4194321) Up(4194320) Down(4194322)
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(4194321): # Right Arrow
		input_dir.x += 1
	if Input.is_physical_key_pressed(4194319): # Left Arrow
		input_dir.x -= 1
	if Input.is_physical_key_pressed(4194322): # Down Arrow
		input_dir.y += 1
	if Input.is_physical_key_pressed(4194320): # Up Arrow
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
	pass

func _try_catch() -> void:
	# Find main player and check proximity
	var player: Node = player1 if player1 != null else get_tree().current_scene.find_child("player", true, false)
	if player and player is CharacterBody2D:
		# Only allow catch if Player 1 is not at base if that property exists
		var eligible := true
		if "at_base" in player:
			eligible = not player.at_base
		if eligible and global_position.distance_to(player.global_position) <= catch_radius:
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

# Player1 signal handlers to control chase eligibility
func on_player_slipper_thrown(_pos: Vector2) -> void:
	can_chase_player = true

func on_player_returned_to_base() -> void:
	can_chase_player = false

func _handle_can_interactions() -> void:
	if can_node == null:
		var found := get_tree().current_scene.find_child("Can", true, false)
		if found and found is Node2D:
			can_node = found
	if can_node == null:
		return
	# Interact only if the node has our helper API
	if can_node and can_node.has_method("is_knocked_down") and can_node.has_method("begin_carry"):
		# Auto-pickup if knocked down and close enough and not already being carried
		var knocked: bool = bool(can_node.call("is_knocked_down"))
		var carried: bool = bool(can_node.get("is_being_carried"))
		if knocked and not carried and global_position.distance_to(can_node.global_position) <= carry_pickup_radius:
			can_node.begin_carry(self)
		# If carrying, auto-drop/reset when near original spot
		var orig_val = can_node.get("original_position")
		var orig: Vector2
		if not (orig_val is Vector2):
			return
		orig = orig_val
		if carried:
			if global_position.distance_to(orig) <= carry_drop_radius:
				if can_node.has_method("end_carry"):
					can_node.end_carry()
				if can_node.has_method("reset_to_original"):
					can_node.reset_to_original()
