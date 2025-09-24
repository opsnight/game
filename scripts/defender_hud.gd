extends Control

@onready var status_label: Label = $MarginContainer/HBoxContainer/StatusLabel

func set_status(status_text: String) -> void:
	if status_label:
		status_label.text = status_text

func set_ammo(count: int, max_count: int) -> void:
	# Defender doesn't use ammo, but keep compatibility
	pass
