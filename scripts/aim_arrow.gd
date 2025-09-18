extends Node2D

@onready var line: Line2D = $Line2D
@onready var tip: Polygon2D = $Tip

@export var length: float = 40.0
@export var color: Color = Color(1, 1, 0, 0.9)

func _ready() -> void:
	line.default_color = color
	tip.color = color
	_set_length(length)

func _set_length(len: float) -> void:
	length = len
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(len, 0)])
	# Simple triangle tip at the end
	tip.polygon = PackedVector2Array([
		Vector2(len, 0),
		Vector2(len - 8, -4),
		Vector2(len - 8, 4),
	])

func point_towards(dir: Vector2) -> void:
	if dir.length() > 0.0:
		rotation = dir.angle()
