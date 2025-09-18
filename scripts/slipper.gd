extends Area2D

signal picked_up

@export var speed: float = 300.0
@export var drag: float = 250.0
@export var pickup_radius: float = 18.0
var velocity: Vector2 = Vector2.ZERO

func init(dir: Vector2) -> void:
	# Initialize direction and rotation
	var d := dir
	if d.length() == 0:
		d = Vector2.DOWN
	velocity = d.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	# Basic projectile motion with drag
	position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, drag * delta)
	if velocity.length() > 0.0:
		rotation = velocity.angle()

	# Proximity pickup: if player is nearby, auto-pick
	var player := get_tree().current_scene.find_child("player", true, false)
	if player and player is CharacterBody2D:
		if global_position.distance_to(player.global_position) <= pickup_radius:
			emit_signal("picked_up")
			queue_free()

func _on_body_entered(body: Node) -> void:
	# Auto-pickup when the player touches the slipper
	if body is CharacterBody2D and ("player" in String(body.name).to_lower() or body.has_method("_on_slipper_picked")):
		emit_signal("picked_up")
		queue_free()
