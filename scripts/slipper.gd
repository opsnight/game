extends Area2D

signal picked_up

@export var speed: float = 300.0
@export var drag: float = 250.0
@export var pickup_radius: float = 18.0
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	if not is_in_group("slipper"):
		add_to_group("slipper")
	# Detect physics bodies we hit (e.g., the can)
	if has_signal("body_entered"):
		connect("body_entered", Callable(self, "_on_body_entered"))

func init(dir: Vector2, power: float = 1.0) -> void:
	# Initialize direction and rotation
	var d: Vector2 = dir
	if d.length() == 0:
		d = Vector2.DOWN
	var p: float = max(0.05, power)
	velocity = d.normalized() * speed * p
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	# Basic projectile motion with drag
	position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, drag * delta)
	if velocity.length() > 0.0:
		rotation = velocity.angle()

	# Proximity pickup: if player is nearby, auto-pick
	var player: Node = get_tree().current_scene.find_child("player", true, false)
	if player and player is CharacterBody2D:
		if global_position.distance_to(player.global_position) <= pickup_radius:
			emit_signal("picked_up")
			queue_free()

func _on_body_entered(body: Node) -> void:
	# Hit the can (RigidBody2D) -> transfer impulse and free slipper
	if body and body.is_in_group("can"):
		if body.has_method("hit_from"):
			body.hit_from(velocity, global_position)
		queue_free()
		return
	# Auto-pickup when the player touches the slipper
	if body is CharacterBody2D and ("player" in String(body.name).to_lower() or body.has_method("_on_slipper_picked")):
		emit_signal("picked_up")
		queue_free()
