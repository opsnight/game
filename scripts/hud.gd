extends Control

@onready var count_label: Label = $MarginContainer/HBoxContainer/Label

func set_ammo(count: int, max_count: int) -> void:
	count_label.text = str(count, " / ", max_count)
