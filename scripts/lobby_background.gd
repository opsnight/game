extends Node2D

@onready var back_button: Button = $BackButton

func _ready() -> void:
	# Make sure the Back button is clickable even if placed on a background node
	if back_button:
		back_button.disabled = false
		back_button.mouse_filter = Control.MOUSE_FILTER_STOP
		back_button.focus_mode = Control.FOCUS_ALL
		if not back_button.pressed.is_connected(_on_back):
			back_button.pressed.connect(_on_back)

func _unhandled_input(event: InputEvent) -> void:
	# ESC also acts as Back
	if event.is_action_pressed("ui_cancel"):
		_on_back()

func _on_back() -> void:
	_cleanup_network()
	# Go back to previous section (Game Selection)
	var game_sel := "res://scenes/game_selection.tscn"
	if ResourceLoader.exists(game_sel):
		get_tree().change_scene_to_file(game_sel)
		return
	# Fallback to main menu
	var menu := "res://scenes/main_menu.tscn"
	if ResourceLoader.exists(menu):
		get_tree().change_scene_to_file(menu)

func _cleanup_network() -> void:
	var mp := get_tree().get_multiplayer()
	if mp and mp.multiplayer_peer != null:
		var peer := mp.multiplayer_peer
		if peer and peer.has_method("close"):
			peer.close()
		mp.multiplayer_peer = null
	# Clear saved roles so next session starts clean
	if Engine.has_singleton("GameConfig"):
		GameConfig.clear_roles()
