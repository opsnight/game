extends CharacterBody2D

signal caught_player

const SPEED: float = 100.0
const ACCELERATION: float = 1500.0
const FRICTION: float = 1200.0
const RUN_MULTIPLIER: float = 1.6
const RUN_ACCEL_MULTIPLIER: float = 1.6

var current_dir: String = "down"
var is_attacking: bool = false
@export var catch_radius: float = 36.0

# References and state
var can_node: Node2D = null
var player1: Node = null
var can_chase_player: bool = false
var carry_pickup_radius: float = 36.0
var carry_drop_radius: float = 24.0
var attack_cooldown: float = 0.0

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
	# Cool down attack window
	if attack_cooldown > 0.0:
		attack_cooldown = max(0.0, attack_cooldown - delta)

func _unhandled_input(event: InputEvent) -> void:
	# Punch on Numpad 0 (KEY_KP_0). Support both keycode and physical_keycode in Godot 4.
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_KP_0 or event.physical_keycode == KEY_KP_0 or Input.is_key_pressed(KEY_KP_0):
			_start_attack()

func _input(event: InputEvent) -> void:
	# Also listen in _input to avoid cases where input is consumed before unhandled phase
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_KP_0 or event.physical_keycode == KEY_KP_0:
			_start_attack()

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
		# Prevent entering Player 1 base: cancel inward component at the boundary
		var p1 := player1 if player1 != null else get_tree().current_scene.find_child("player", true, false)
		if p1:
			var base_center_val = p1.get("base_center")
			var base_radius_val = p1.get("base_radius")
			var base_center: Vector2
			var base_radius: float
			if (base_center_val is Vector2) and (typeof(base_radius_val) == TYPE_FLOAT or typeof(base_radius_val) == TYPE_INT):
				base_center = base_center_val
				base_radius = float(base_radius_val)
				var to_center: Vector2 = (base_center - global_position)
				var dist: float = to_center.length()
				if dist > 0.0:
					var inward: Vector2 = to_center / dist
					var inward_comp := input_dir.dot(inward)
					# If at/inside boundary and trying to go further inward, cancel inward motion
					if dist <= base_radius + 1.0 and inward_comp > 0.0:
						input_dir = (input_dir - inward * inward_comp).normalized() if (input_dir - inward * inward_comp).length() > 0.001 else Vector2.ZERO
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
	if is_attacking or attack_cooldown > 0.0:
		return
	is_attacking = true
	attack_cooldown = 0.45
	print("[P2] Punch started (KP_0)")
	# Try an immediate catch check within the punch window
	_try_catch_punch()
	# Play attack anim if exists
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	var base: String = _base_from_dir(current_dir)
	var flip_left: bool = current_dir in ["left", "down_left", "up_left"]
	anim.flip_h = flip_left
	var name: String = base + "_attack"
	if anim.sprite_frames and anim.sprite_frames.has_animation(name):
		anim.play(name)
	# End attack after short window
	await get_tree().create_timer(0.3).timeout
	is_attacking = false

func _try_catch() -> void:
	# Find main player and check proximity
	var player: Node = player1 if player1 != null else get_tree().current_scene.find_child("player", true, false)
	if player and player is CharacterBody2D:
		# Catch only via punch: must be attacking, player vulnerable, and can returned
		if not is_attacking:
			return
		var vulnerable := bool(player.get("is_vulnerable")) if player.has_method("get") else false
		if not vulnerable:
			return
		if not _is_can_at_origin():
			return
		if global_position.distance_to(player.global_position) <= catch_radius:
			emit_signal("caught_player")
			if player.has_method("play_hurt_from"):
				player.play_hurt_from(global_position)

func _try_catch_punch() -> void:
	# Catch only if Player 1 is vulnerable (red aura) and can has been returned
	var player: Node = player1 if player1 != null else get_tree().current_scene.find_child("player", true, false)
	if not (player and player is CharacterBody2D):
		print("[P2] No player found for punch")
		return
	var vulnerable := bool(player.get("is_vulnerable")) if player.has_method("get") else false
	if not vulnerable:
		print("[P2] Punch ignored: player not vulnerable")
		return
	if not _is_can_at_origin():
		print("[P2] Punch ignored: can not at origin")
		return
	if global_position.distance_to((player as Node2D).global_position) <= catch_radius:
		emit_signal("caught_player")
		if player.has_method("play_hurt_from"):
			player.play_hurt_from(global_position)
	else:
		print("[P2] Punch missed: out of range (d=", global_position.distance_to((player as Node2D).global_position), ")")

func _is_can_at_origin() -> bool:
	if can_node == null:
		return true # treat as back to avoid blocking if can not present
	var carried := bool(can_node.get("is_being_carried"))
	if carried:
		return false
	if can_node.has_method("is_knocked_down"):
		return not bool(can_node.call("is_knocked_down"))
	# Fallback to distance check if helpers missing
	var orig_val = can_node.get("original_position")
	if not (orig_val is Vector2):
		return true
	var orig: Vector2 = orig_val
	return can_node.global_position.distance_to(orig) <= 2.0

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
