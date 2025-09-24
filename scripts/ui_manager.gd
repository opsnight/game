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

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "Score: " + str(new_score)
func show_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = true
	if final_score_label and game_manager:
		final_score_label.text = "Final Score: " + str(game_manager.score)

func hide_game_over() -> void:
	if game_over_panel:
		game_over_panel.visible = false

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
