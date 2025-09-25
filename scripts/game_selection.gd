extends Node2D

@onready var lan_button: Button = $UI/Panel/VBox/LANButton
@onready var local_button: Button = $UI/Panel/VBox/LocalButton
@onready var back_button: Button = $UI/Panel/VBox/BackButton

func _ready() -> void:
	if lan_button:
		lan_button.pressed.connect(_on_lan)
	if local_button:
		local_button.pressed.connect(_on_local)
	if back_button:
		back_button.pressed.connect(_on_back)

func _on_lan() -> void:
	# Tag mode for downstream logic and keep existing peer state (set by lobby)
	if Engine.has_singleton("GameConfig"):
		GameConfig.mode = GameConfig.Mode.MULTIPLAYER
	get_tree().change_scene_to_file("res://scenes/Multiplayer_Lobby.tscn")

func _on_local() -> void:
	# Ensure we are fully offline. Clear any existing multiplayer peer.
	multiplayer.multiplayer_peer = null
	if Engine.has_singleton("GameConfig"):
		GameConfig.mode = GameConfig.Mode.SINGLEPLAYER
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_back() -> void:
	var menu_path := "res://scenes/main_menu.tscn"
	if ResourceLoader.exists(menu_path):
		get_tree().change_scene_to_file(menu_path)
	else:
		print("Main menu scene not found at ", menu_path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
