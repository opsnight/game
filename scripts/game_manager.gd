extends Node

signal game_over()
signal score_changed(new_score: int)
signal can_hit()

@export var game_scene: PackedScene

var score: int = 0
var game_active: bool = true
var ui_manager: Node = null

func _ready() -> void:
	# Connect to slipper signals
	_connect_slipper_signals()
	
	# Connect to defender AI
	var defender = get_tree().get_first_node_in_group("defender")
	if defender and defender.has_signal("caught_slipper"):
		defender.connect("caught_slipper", Callable(self, "_on_ai_caught_slipper"))

func _connect_slipper_signals() -> void:
	# Connect to existing slippers and watch for new ones
	for slipper in get_tree().get_nodes_in_group("slipper"):
		_connect_to_slipper(slipper)
	
	# Listen for new slippers being created
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.is_in_group("slipper"):
		_connect_to_slipper(node)

func _connect_to_slipper(slipper: Node) -> void:
	if slipper.has_signal("ai_picked_up"):
		slipper.connect("ai_picked_up", Callable(self, "_on_ai_caught_slipper"))

func _on_ai_caught_slipper() -> void:
	if not game_active:
		return
	
	game_active = false
	emit_signal("game_over")
	
	# Show game over UI
	if ui_manager and ui_manager.has_method("show_game_over"):
		ui_manager.show_game_over()

func add_score(points: int) -> void:
	if not game_active:
		return
	
	score += points
	emit_signal("score_changed", score)
	emit_signal("can_hit")

func restart_game() -> void:
	score = 0
	game_active = true
	emit_signal("score_changed", score)
	
	# Reset can position
	var can = get_tree().get_first_node_in_group("can")
	if can and can.has_method("restore"):
		can.restore()
	
	# Clear any slippers on ground
	for slipper in get_tree().get_nodes_in_group("slipper"):
		if slipper.has_method("is_on_ground") and slipper.is_on_ground():
			slipper.queue_free()
	
	# Reset player ammo
	var player = get_tree().current_scene.find_child("player", true, false)
	if player and "slippers_available" in player and "MAX_SLIPPERS" in player:
		player.slippers_available = player.MAX_SLIPPERS
		if player.has_signal("ammo_changed"):
			player.emit_signal("ammo_changed", player.slippers_available, player.MAX_SLIPPERS)
	
	# Hide game over UI
	if ui_manager and ui_manager.has_method("hide_game_over"):
		ui_manager.hide_game_over()

func set_ui_manager(ui: Node) -> void:
	ui_manager = ui
