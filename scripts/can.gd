extends RigidBody2D

@export var hit_impulse_scale: float = 1.2
@export var min_impulse: float = 150.0

func _ready() -> void:
	# Enable contact monitoring so body_entered works on RigidBody2D
	contact_monitor = true
	max_contacts_reported = 8
	gravity_scale = 0.0
	linear_damp = 6.0
	angular_damp = 6.0
	if not is_in_group("can"):
		add_to_group("can")
	self.body_entered.connect(Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("slipper"):
		_apply_hit_from(body)

func _apply_hit_from(node: Node) -> void:
	var impulse: Vector2 = Vector2.ZERO
	if "velocity" in node:
		var v: Vector2 = node.velocity
		impulse = v * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - node.global_position)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)

func hit_from(vel: Vector2, hit_pos: Vector2) -> void:
	# Public API for Area2D (slipper) to notify hits
	var impulse := vel * hit_impulse_scale
	if impulse.length() < min_impulse:
		var dir: Vector2 = (global_position - hit_pos)
		if dir.length() == 0:
			dir = Vector2.UP
		impulse = dir.normalized() * min_impulse
	apply_impulse(impulse)
