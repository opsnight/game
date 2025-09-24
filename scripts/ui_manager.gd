extends CanvasLayer

@onready var score_label: Label = $UI/ScoreLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/VBoxContainer/GameOverLabel
@onready var final_score_label: Label = $UI/GameOverPanel/VBoxContainer/FinalScoreLabel
@onready var restart_button: Button = $UI/GameOverPanel/VBoxContainer/RestartButton

var game_manager: Node = null

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
