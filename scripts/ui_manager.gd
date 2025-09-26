extends CanvasLayer

@onready var score_label: Label = $UI/ScoreLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/VBoxContainer/GameOverLabel
@onready var final_score_label: Label = $UI/GameOverPanel/VBoxContainer/FinalScoreLabel
@onready var restart_button: Button = $UI/GameOverPanel/VBoxContainer/RestartButton

var game_manager: Node = null

# Emitted on the defender client when they pick a new defender.
signal defender_selected(peer_id: int)

var _defender_select_panel: Control = null

func _ready() -> void:
	# Hide game over panel initially
	if game_over_panel:
		game_over_panel.visible = false
	
	# Connect restart button
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)

func set_game_manager(gm: Node) -> void:
	game_manager = gm
	if game_manager:
		if game_manager.has_signal("score_changed"):
			game_manager.connect("score_changed", Callable(self, "_on_score_changed"))
		if game_manager.has_signal("game_over"):
			game_manager.connect("game_over", Callable(self, "show_game_over"))
		# Hook can hits for visual stingers
		if game_manager.has_signal("can_hit"):
			game_manager.connect("can_hit", Callable(self, "_on_can_hit_stinger"))

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "Score: " + str(new_score)
func show_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = true
	if final_score_label and game_manager:
		final_score_label.text = "Final Score: " + str(game_manager.score)
	# Present a themed caught dialog for local mode
	_show_caught_modal("Player 1 got caught!\nWant to try again?")

func hide_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = false
	# Also remove any modal if present
	var modal := $UI.get_node_or_null("CaughtModal")
	if modal:
		modal.queue_free()

func show_caught_modal() -> void:
	_show_caught_modal("Player 1 got caught!\nWant to try again?")

func _show_caught_modal(message: String) -> void:
	# Build a simple modal overlay with message and buttons
	var root := $UI
	if root == null:
		return
	# Remove existing
	var existing := root.get_node_or_null("CaughtModal")
	if existing:
		existing.queue_free()
	var panel := Control.new()
	panel.name = "CaughtModal"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	root.add_child(panel)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	panel.add_child(overlay)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -180
	box.offset_top = -120
	box.offset_right = 180
	box.offset_bottom = 120
	panel.add_child(box)

	var title := Label.new()
	title.text = message
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	var try_again := Button.new()
	try_again.text = "Play Again"
	try_again.custom_minimum_size = Vector2(120, 36)
	try_again.pressed.connect(Callable(self, "_on_try_again_pressed"))
	buttons.add_child(try_again)

	var to_menu := Button.new()
	to_menu.text = "Main Menu"
	to_menu.custom_minimum_size = Vector2(120, 36)
	to_menu.pressed.connect(Callable(self, "_on_main_menu_pressed"))
	buttons.add_child(to_menu)

func _on_try_again_pressed() -> void:
	if game_manager and game_manager.has_method("restart_game"):
		game_manager.restart_game()
	hide_game_over()

func _on_main_menu_pressed() -> void:
	# Go back to main menu scene if available
	if ResourceLoader.exists("res://scenes/main_menu.tscn"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_can_hit_stinger() -> void:
	if not Engine.has_singleton("GameConfig"):
		return
	if not GameConfig.presentation_pack:
		return
	# Simple flash overlay and text stinger
	var overlay := ColorRect.new()
	overlay.color = Color(1, 1, 1, 0.0)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	$UI.add_child(overlay)
	# Fade in/out quickly
	await _flash_overlay(overlay, 0.08, 0.25)
	if is_instance_valid(overlay):
		overlay.queue_free()

func _flash_overlay(node: ColorRect, peak: float, duration: float) -> void:
	var half: float = max(0.01, duration * 0.5)
	var t := 0.0
	while t < half:
		t += get_process_delta_time()
		node.color.a = lerp(0.0, peak, clamp(t / half, 0.0, 1.0))
		await get_tree().process_frame
	while t < duration:
		t += get_process_delta_time()
		node.color.a = lerp(peak, 0.0, clamp((t - half) / half, 0.0, 1.0))
		await get_tree().process_frame

func _on_restart_pressed() -> void:
	if game_manager and game_manager.has_method("restart_game"):
		game_manager.restart_game()

# --- Defender selection (LAN) ---
func show_defender_select(attackers: Array) -> void:
	# attackers is an Array of peer IDs
	if _defender_select_panel and is_instance_valid(_defender_select_panel):
		_defender_select_panel.queue_free()
		_defender_select_panel = null

	var panel := Control.new()
	panel.name = "DefenderSelectPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	panel.add_child(overlay)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -150
	box.offset_top = -120
	box.offset_right = 150
	box.offset_bottom = 120
	panel.add_child(box)

	var title := Label.new()
	title.text = "Choose new defender"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)

	for pid in attackers:
		var btn := Button.new()
		btn.text = "Peer %d" % int(pid)
		btn.pressed.connect(Callable(self, "_on_select_defender_btn").bind(int(pid)))
		grid.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(Callable(self, "hide_defender_select"))
	box.add_child(cancel)

	$UI.add_child(panel)
	_defender_select_panel = panel

func hide_defender_select() -> void:
	if _defender_select_panel and is_instance_valid(_defender_select_panel):
		_defender_select_panel.queue_free()
	_defender_select_panel = null

func _on_select_defender_btn(pid: int) -> void:
	emit_signal("defender_selected", pid)
	hide_defender_select()
