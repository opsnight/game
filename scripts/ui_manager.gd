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
var _pause_menu: Control = null
var _options_menu: Control = null
var _exit_confirmation: Control = null
var _is_paused: bool = false

func _ready() -> void:
	# Hide game over panel initially
	if game_over_panel:
		game_over_panel.visible = false
	
	# Connect restart button
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# Handle ESC key for pause menu
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause_menu()

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
		# Add smooth fade-in animation
		game_over_panel.modulate = Color(1, 1, 1, 0)
		var tween := create_tween()
		tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.5)
		tween.tween_callback(_add_game_over_bounce)
	
	if final_score_label and game_manager:
		final_score_label.text = "Final Score: " + str(game_manager.score)
	
	# Present a themed caught dialog for local mode with enhanced effects
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
	# Build an enhanced modal overlay with smooth animations
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

	# Animated overlay background
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	panel.add_child(overlay)
	
	# Animate overlay fade-in
	var overlay_tween := create_tween()
	overlay_tween.tween_property(overlay, "color:a", 0.7, 0.3)

	# Main dialog box with enhanced styling
	var dialog_bg := NinePatchRect.new()
	dialog_bg.anchor_left = 0.5
	dialog_bg.anchor_top = 0.5
	dialog_bg.anchor_right = 0.5
	dialog_bg.anchor_bottom = 0.5
	dialog_bg.offset_left = -200
	dialog_bg.offset_top = -140
	dialog_bg.offset_right = 200
	dialog_bg.offset_bottom = 140
	
	# Create a simple colored background if no ninepatch texture
	var bg_color := ColorRect.new()
	bg_color.color = Color(0.2, 0.2, 0.3, 0.95)
	bg_color.anchor_left = 0.0
	bg_color.anchor_top = 0.0
	bg_color.anchor_right = 1.0
	bg_color.anchor_bottom = 1.0
	dialog_bg.add_child(bg_color)
	
	panel.add_child(dialog_bg)

	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 20
	box.offset_top = 20
	box.offset_right = -20
	box.offset_bottom = -20
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_bg.add_child(box)

	# Enhanced title with better styling
	var title := Label.new()
	title.text = message
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.custom_minimum_size = Vector2(0, 80)
	box.add_child(title)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	# Enhanced buttons with hover effects
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)

	var try_again := Button.new()
	try_again.text = "Play Again"
	try_again.custom_minimum_size = Vector2(140, 45)
	try_again.add_theme_font_size_override("font_size", 16)
	try_again.pressed.connect(Callable(self, "_on_try_again_pressed"))
	_style_modal_button(try_again, Color(0.2, 0.7, 0.2))
	buttons.add_child(try_again)

	var to_menu := Button.new()
	to_menu.text = "Main Menu"
	to_menu.custom_minimum_size = Vector2(140, 45)
	to_menu.add_theme_font_size_override("font_size", 16)
	to_menu.pressed.connect(Callable(self, "_on_main_menu_pressed"))
	_style_modal_button(to_menu, Color(0.7, 0.2, 0.2))
	buttons.add_child(to_menu)
	
	# Animate dialog entrance with bounce effect
	dialog_bg.scale = Vector2(0.3, 0.3)
	dialog_bg.modulate = Color(1, 1, 1, 0)
	
	var dialog_tween := create_tween()
	dialog_tween.set_parallel(true)
	dialog_tween.tween_property(dialog_bg, "scale", Vector2(1.1, 1.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dialog_tween.tween_property(dialog_bg, "modulate:a", 1.0, 0.2)
	
	# Settle to normal size
	await dialog_tween.finished
	var settle_tween := create_tween()
	settle_tween.tween_property(dialog_bg, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_try_again_pressed() -> void:
	if game_manager and game_manager.has_method("restart_game"):
		game_manager.restart_game()
	hide_game_over()

func _on_main_menu_pressed() -> void:
	# Go back to main menu scene if available
	if ResourceLoader.exists("res://scenes/main_menu.tscn"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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

func _add_game_over_bounce() -> void:
	# Add a subtle bounce effect to the game over panel
	if game_over_panel:
		var bounce_tween := create_tween()
		bounce_tween.tween_property(game_over_panel, "scale", Vector2(1.05, 1.05), 0.1)
		bounce_tween.tween_property(game_over_panel, "scale", Vector2(1.0, 1.0), 0.1)

func _style_modal_button(button: Button, base_color: Color) -> void:
	# Add custom styling to modal buttons
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = base_color
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = base_color.lightened(0.2)
	style_hover.corner_radius_top_left = 8
	style_hover.corner_radius_top_right = 8
	style_hover.corner_radius_bottom_left = 8
	style_hover.corner_radius_bottom_right = 8
	
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = base_color.darkened(0.2)
	style_pressed.corner_radius_top_left = 8
	style_pressed.corner_radius_top_right = 8
	style_pressed.corner_radius_bottom_left = 8
	style_pressed.corner_radius_bottom_right = 8
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_color_override("font_color", Color.WHITE)

func _on_can_hit_stinger() -> void:
	if not Engine.has_singleton("GameConfig"):
		return
	if not GameConfig.presentation_pack:
		return
	
	# Enhanced visual effects for can hits
	_create_screen_shake()
	_create_hit_flash()
	_create_score_popup()

func _create_screen_shake() -> void:
	# Simple screen shake effect
	var camera := get_viewport().get_camera_2d()
	if camera:
		var original_offset := camera.offset
		var shake_tween := create_tween()
		shake_tween.set_loops(6)
		shake_tween.tween_method(_shake_camera.bind(camera, original_offset), 0.0, 1.0, 0.05)
		shake_tween.tween_callback(func(): camera.offset = original_offset)

func _shake_camera(camera: Camera2D, original_offset: Vector2, intensity: float) -> void:
	var shake_amount := 8.0 * (1.0 - intensity)
	var random_offset := Vector2(
		randf_range(-shake_amount, shake_amount),
		randf_range(-shake_amount, shake_amount)
	)
	camera.offset = original_offset + random_offset

func _create_hit_flash() -> void:
	# Enhanced flash effect
	var overlay := ColorRect.new()
	overlay.color = Color(1, 1, 0.8, 0.0)  # Yellowish flash
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	$UI.add_child(overlay)
	
	var flash_tween := create_tween()
	flash_tween.tween_property(overlay, "color:a", 0.4, 0.05)
	flash_tween.tween_property(overlay, "color:a", 0.0, 0.15)
	flash_tween.tween_callback(func(): overlay.queue_free())

func _create_score_popup() -> void:
	# Score popup effect
	var popup := Label.new()
	popup.text = "+10 POINTS!"
	popup.add_theme_font_size_override("font_size", 24)
	popup.add_theme_color_override("font_color", Color.YELLOW)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.anchor_left = 0.5
	popup.anchor_right = 0.5
	popup.anchor_top = 0.3
	popup.anchor_bottom = 0.3
	popup.offset_left = -100
	popup.offset_right = 100
	popup.modulate = Color(1, 1, 1, 0)
	$UI.add_child(popup)
	
	var popup_tween := create_tween()
	popup_tween.set_parallel(true)
	popup_tween.tween_property(popup, "modulate:a", 1.0, 0.2)
	popup_tween.tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	popup_tween.tween_property(popup, "modulate:a", 0.0, 0.3).set_delay(0.7)
	popup_tween.tween_callback(func(): popup.queue_free()).set_delay(1.0)

func _on_select_defender_btn(pid: int) -> void:
	emit_signal("defender_selected", pid)
	hide_defender_select()

# === PAUSE MENU SYSTEM ===

func _toggle_pause_menu() -> void:
	if _is_paused:
		_hide_pause_menu()
	else:
		_show_pause_menu()

func _show_pause_menu() -> void:
	if _is_paused:
		return
		
	print("[UIManager] Showing pause menu")
	_is_paused = true
	get_tree().paused = true
	
	# Create pause menu if it doesn't exist
	if not _pause_menu:
		_create_pause_menu()
	
	_pause_menu.visible = true
	
	# Animate entrance
	_pause_menu.modulate = Color(1, 1, 1, 0)
	_pause_menu.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_pause_menu, "modulate:a", 1.0, 0.3)
	tween.tween_property(_pause_menu, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_pause_menu() -> void:
	if not _is_paused:
		return
		
	print("[UIManager] Hiding pause menu")
	_is_paused = false
	get_tree().paused = false
	
	if _pause_menu:
		_pause_menu.visible = false
	if _options_menu:
		_options_menu.visible = false
	if _exit_confirmation:
		_exit_confirmation.visible = false

func _create_pause_menu() -> void:
	# Create main pause menu container
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	$UI.add_child(_pause_menu)
	
	# Semi-transparent background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(bg)
	
	# Main dialog container
	var dialog := PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	dialog.anchor_left = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -150  # Half of width (300/2)
	dialog.offset_right = 150   # Half of width (300/2)
	dialog.offset_top = -200    # Half of height (400/2)
	dialog.offset_bottom = 200  # Half of height (400/2)
	dialog.custom_minimum_size = Vector2(300, 400)
	_pause_menu.add_child(dialog)
	
	# Style the dialog
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.6, 1.0)
	dialog.add_theme_stylebox_override("panel", style)
	
	# Content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dialog.add_child(vbox)
	
	# Add margins
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	vbox.add_child(margin)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	margin.add_child(content)
	
	# Title
	var title := Label.new()
	title.text = "GAME PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(title)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	content.add_child(spacer)
	
	# Buttons
	var play_again_btn := Button.new()
	play_again_btn.text = "Play Again"
	play_again_btn.custom_minimum_size = Vector2(200, 45)
	play_again_btn.pressed.connect(_on_pause_play_again)
	_style_pause_button(play_again_btn, Color(0.2, 0.7, 0.2))
	content.add_child(play_again_btn)
	
	var options_btn := Button.new()
	options_btn.text = "Options"
	options_btn.custom_minimum_size = Vector2(200, 45)
	options_btn.pressed.connect(_on_pause_options)
	_style_pause_button(options_btn, Color(0.2, 0.5, 0.7))
	content.add_child(options_btn)
	
	var end_game_btn := Button.new()
	end_game_btn.text = "End Game"
	end_game_btn.custom_minimum_size = Vector2(200, 45)
	end_game_btn.pressed.connect(_on_pause_end_game)
	_style_pause_button(end_game_btn, Color(0.7, 0.2, 0.2))
	content.add_child(end_game_btn)
	
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(200, 45)
	resume_btn.pressed.connect(_on_pause_resume)
	_style_pause_button(resume_btn, Color(0.5, 0.5, 0.5))
	content.add_child(resume_btn)

func _style_pause_button(button: Button, base_color: Color) -> void:
	button.add_theme_font_size_override("font_size", 16)
	
	# Normal state
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = base_color
	style_normal.corner_radius_top_left = 5
	style_normal.corner_radius_top_right = 5
	style_normal.corner_radius_bottom_left = 5
	style_normal.corner_radius_bottom_right = 5
	button.add_theme_stylebox_override("normal", style_normal)
	
	# Hover state
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = base_color * 1.2
	style_hover.corner_radius_top_left = 5
	style_hover.corner_radius_top_right = 5
	style_hover.corner_radius_bottom_left = 5
	style_hover.corner_radius_bottom_right = 5
	button.add_theme_stylebox_override("hover", style_hover)
	
	# Pressed state
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = base_color * 0.8
	style_pressed.corner_radius_top_left = 5
	style_pressed.corner_radius_top_right = 5
	style_pressed.corner_radius_bottom_left = 5
	style_pressed.corner_radius_bottom_right = 5
	button.add_theme_stylebox_override("pressed", style_pressed)
	
	button.add_theme_color_override("font_color", Color.WHITE)

# Pause menu button handlers
func _on_pause_resume() -> void:
	_hide_pause_menu()

func _on_pause_play_again() -> void:
	_hide_pause_menu()
	if game_manager and game_manager.has_method("restart_game"):
		game_manager.restart_game()

func _on_pause_options() -> void:
	_show_options_menu()

func _on_pause_end_game() -> void:
	_show_exit_confirmation()

# === OPTIONS MENU ===

func _show_options_menu() -> void:
	if not _options_menu:
		_create_options_menu()
	
	_pause_menu.visible = false
	_options_menu.visible = true
	
	# Animate entrance
	_options_menu.modulate = Color(1, 1, 1, 0)
	_options_menu.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_options_menu, "modulate:a", 1.0, 0.3)
	tween.tween_property(_options_menu, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_options_menu() -> void:
	# Create options menu container
	_options_menu = Control.new()
	_options_menu.name = "OptionsMenu"
	_options_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_options_menu.visible = false
	$UI.add_child(_options_menu)
	
	# Semi-transparent background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_menu.add_child(bg)
	
	# Main dialog container
	var dialog := PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	dialog.anchor_left = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -175  # Half of width (350/2)
	dialog.offset_right = 175   # Half of width (350/2)
	dialog.offset_top = -150    # Half of height (300/2)
	dialog.offset_bottom = 150  # Half of height (300/2)
	dialog.custom_minimum_size = Vector2(350, 300)
	_options_menu.add_child(dialog)
	
	# Style the dialog
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.6, 1.0)
	dialog.add_theme_stylebox_override("panel", style)
	
	# Content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dialog.add_child(vbox)
	
	# Add margins
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	vbox.add_child(margin)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	margin.add_child(content)
	
	# Title
	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(title)
	
	# Master Volume
	var master_label := Label.new()
	master_label.text = "Master Volume"
	master_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(master_label)
	
	var master_slider := HSlider.new()
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.1
	master_slider.value = AudioServer.get_bus_volume_db(0) / 80.0 + 1.0  # Convert from dB
	master_slider.custom_minimum_size = Vector2(250, 30)
	master_slider.value_changed.connect(_on_master_volume_changed)
	content.add_child(master_slider)
	
	# Music Volume
	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(music_label)
	
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.1
	music_slider.value = 0.7  # Default music volume
	music_slider.custom_minimum_size = Vector2(250, 30)
	music_slider.value_changed.connect(_on_music_volume_changed)
	content.add_child(music_slider)
	
	# SFX Volume
	var sfx_label := Label.new()
	sfx_label.text = "SFX Volume"
	sfx_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(sfx_label)
	
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.1
	sfx_slider.value = 0.8  # Default SFX volume
	sfx_slider.custom_minimum_size = Vector2(250, 30)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	content.add_child(sfx_slider)
	
	# Back button
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 40)
	back_btn.pressed.connect(_on_options_back)
	_style_pause_button(back_btn, Color(0.5, 0.5, 0.5))
	content.add_child(back_btn)

# Volume control handlers
func _on_master_volume_changed(value: float) -> void:
	var db_value := (value - 1.0) * 80.0  # Convert to dB range (-80 to 0)
	AudioServer.set_bus_volume_db(0, db_value)
	print("[UIManager] Master volume set to: %.1f" % value)

func _on_music_volume_changed(value: float) -> void:
	# Find music bus (assuming it exists)
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus != -1:
		var db_value := (value - 1.0) * 80.0
		AudioServer.set_bus_volume_db(music_bus, db_value)
	print("[UIManager] Music volume set to: %.1f" % value)

func _on_sfx_volume_changed(value: float) -> void:
	# Find SFX bus (assuming it exists)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		var db_value := (value - 1.0) * 80.0
		AudioServer.set_bus_volume_db(sfx_bus, db_value)
	print("[UIManager] SFX volume set to: %.1f" % value)

func _on_options_back() -> void:
	_options_menu.visible = false
	_pause_menu.visible = true

# === EXIT CONFIRMATION ===

func _show_exit_confirmation() -> void:
	if not _exit_confirmation:
		_create_exit_confirmation()
	
	_pause_menu.visible = false
	_exit_confirmation.visible = true
	
	# Animate entrance
	_exit_confirmation.modulate = Color(1, 1, 1, 0)
	_exit_confirmation.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_exit_confirmation, "modulate:a", 1.0, 0.3)
	tween.tween_property(_exit_confirmation, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_exit_confirmation() -> void:
	# Create exit confirmation container
	_exit_confirmation = Control.new()
	_exit_confirmation.name = "ExitConfirmation"
	_exit_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exit_confirmation.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_exit_confirmation.visible = false
	$UI.add_child(_exit_confirmation)
	
	# Semi-transparent background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exit_confirmation.add_child(bg)
	
	# Main dialog container
	var dialog := PanelContainer.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	dialog.anchor_left = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -150  # Half of width (300/2)
	dialog.offset_right = 150   # Half of width (300/2)
	dialog.offset_top = -100    # Half of height (200/2)
	dialog.offset_bottom = 100  # Half of height (200/2)
	dialog.custom_minimum_size = Vector2(300, 200)
	_exit_confirmation.add_child(dialog)
	
	# Style the dialog
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.2, 0.2, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.4, 0.4, 1.0)
	dialog.add_theme_stylebox_override("panel", style)
	
	# Content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dialog.add_child(vbox)
	
	# Add margins
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	vbox.add_child(margin)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	margin.add_child(content)
	
	# Confirmation message
	var message := Label.new()
	message.text = "Are you sure you want to exit?"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 16)
	message.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(message)
	
	# Button container
	var button_container := HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	content.add_child(button_container)
	
	# Yes button
	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	yes_btn.custom_minimum_size = Vector2(80, 40)
	yes_btn.pressed.connect(_on_exit_yes)
	_style_pause_button(yes_btn, Color(0.7, 0.2, 0.2))
	button_container.add_child(yes_btn)
	
	# No button
	var no_btn := Button.new()
	no_btn.text = "No"
	no_btn.custom_minimum_size = Vector2(80, 40)
	no_btn.pressed.connect(_on_exit_no)
	_style_pause_button(no_btn, Color(0.2, 0.7, 0.2))
	button_container.add_child(no_btn)

func _on_exit_yes() -> void:
	print("[UIManager] Exiting to main menu")
	_hide_pause_menu()
	# Go to main menu
	if ResourceLoader.exists("res://scenes/main_menu.tscn"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	else:
		print("[UIManager] Main menu scene not found")

func _on_exit_no() -> void:
	_exit_confirmation.visible = false
	_pause_menu.visible = true
