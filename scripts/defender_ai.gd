extends CharacterBody2D

signal caught_slipper()

@export var speed: float = 120.0
@export var idle_radius: float = 80.0
@export var detection_range: float = 300.0

var can_node: Node2D = null
var can_original_position: Vector2
var target_slipper: Node2D = null
var state: String = "idle"  # "idle", "chasing", "restoring_can"
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# Find the can and store its original position
	can_node = get_tree().get_first_node_in_group("can")
	if can_node:
		can_original_position = can_node.global_position

func _physics_process(delta: float) -> void:
	match state:
		"idle":
			_idle_behavior()
		"chasing":
			_chase_slipper()
		"restoring_can":
			_restore_can()
	
	move_and_slide()
	_update_animation()

func _idle_behavior() -> void:
	# Look for slippers on the ground
	var closest_slipper = _find_closest_slipper()
	if closest_slipper:
		target_slipper = closest_slipper
		state = "chasing"
		return
	
	# Patrol around the can
	if can_node:
		var to_can = can_node.global_position - global_position
		var distance_to_can = to_can.length()
		
		if distance_to_can > idle_radius:
			# Move back toward can
			velocity = to_can.normalized() * speed * 0.5
		else:
			# Slow patrol movement
			var patrol_angle = Time.get_ticks_msec() * 0.001
			var patrol_offset = Vector2(cos(patrol_angle), sin(patrol_angle)) * idle_radius * 0.3
			var target_pos = can_node.global_position + patrol_offset
			var to_target = target_pos - global_position
			velocity = to_target.normalized() * speed * 0.3

func _chase_slipper() -> void:
	if not target_slipper or not target_slipper.is_inside_tree():
		target_slipper = null
		state = "idle"
		return
	
	# Check if slipper is still on ground (not being thrown)
	if target_slipper.has_method("is_on_ground") and not target_slipper.is_on_ground():
		target_slipper = null
		state = "idle"
		return
	
	# Move toward the slipper
	var to_slipper = target_slipper.global_position - global_position
	var distance = to_slipper.length()
	
	if distance < 20.0:
		# Reached the slipper - game over
		if target_slipper.has_method("ai_pickup"):
			target_slipper.ai_pickup()
		emit_signal("caught_slipper")
		target_slipper = null
		state = "idle"
	else:
		velocity = to_slipper.normalized() * speed

func _restore_can() -> void:
	if not can_node:
		state = "idle"
		return
	
	# Move to can and restore it
	var to_can = can_original_position - global_position
	var distance = to_can.length()
	
	if distance < 30.0:
		# Close enough to restore can
		can_node.global_position = can_original_position
		if can_node.has_method("restore"):
			can_node.restore()
		state = "idle"
	else:
		velocity = to_can.normalized() * speed

func _find_closest_slipper() -> Node2D:
	var closest: Node2D = null
	var closest_distance: float = INF
	
	for slipper in get_tree().get_nodes_in_group("slipper"):
		if slipper is Node2D and slipper.is_inside_tree():
			# Only target slippers that are on the ground
			if slipper.has_method("is_on_ground") and slipper.is_on_ground():
				var distance = global_position.distance_to(slipper.global_position)
				if distance < detection_range and distance < closest_distance:
					closest = slipper
					closest_distance = distance
	
	return closest

func on_can_hit() -> void:
	# Called when the can is hit - start restoration after delay
	await get_tree().create_timer(1.5).timeout
	if state == "idle" or state == "chasing":
		state = "restoring_can"

func _update_animation() -> void:
	if anim == null:
		return
	var moving: bool = velocity.length() > 5.0
	var desired: String = "f_idle"
	if moving:
		desired = "f_walk"
	var frames := anim.sprite_frames
	if frames and frames.has_animation(desired) and anim.animation != desired:
		anim.play(desired)
	anim.flip_h = velocity.x < 0.0
