extends Control

# Creates a fully functional Options UI with audio controls
# - Master, Music, SFX sliders with live feedback and persistence
# - Back button to return to previous scene
# - Visual feedback with percentage labels

var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var master_label: Label
var music_label: Label
var sfx_label: Label
var back_btn: Button

func _ready() -> void:
	_create_ui()
	_load_and_apply_settings()
	_connect_signals()
	
	# Apply volumes immediately to ensure they work
	call_deferred("_apply_current_volumes")

func _create_ui() -> void:
	# Main container
	var main_box := VBoxContainer.new()
	main_box.anchor_left = 0.5
	main_box.anchor_top = 0.5
	main_box.anchor_right = 0.5
	main_box.anchor_bottom = 0.5
	main_box.offset_left = -200
	main_box.offset_top = -150
	main_box.offset_right = 200
	main_box.offset_bottom = 150
	main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(main_box)

	# Title
	var title := Label.new()
	title.text = "Audio Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_box.add_child(title)
	
	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	main_box.add_child(spacer1)

	# Master Volume
	_create_volume_row(main_box, "Master Volume", "master")
	
	# Music Volume  
	_create_volume_row(main_box, "Music Volume", "music")
	
	# SFX Volume
	_create_volume_row(main_box, "SFX Volume", "sfx")
	
	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	main_box.add_child(spacer2)

	# Back Button
	back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 40)
	main_box.add_child(back_btn)

func _create_volume_row(parent: VBoxContainer, label_text: String, type: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	
	# Label with percentage
	var label := Label.new()
	label.text = label_text + ": 100%"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)
	
	# Slider
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(300, 30)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 1.0
	row.add_child(slider)
	
	# Store references
	match type:
		"master":
			master_slider = slider
			master_label = label
		"music":
			music_slider = slider
			music_label = label
		"sfx":
			sfx_slider = slider
			sfx_label = label
	
	# Add some spacing
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	row.add_child(spacer)

func _load_and_apply_settings() -> void:
	var am := _get_audio_manager()
	if not am:
		print("[Options] AudioManager not found - using defaults")
		return
		
	print("[Options] Loading settings from AudioManager...")
	
	# Load current values
	master_slider.value = am.master_volume
	music_slider.value = am.music_volume
	sfx_slider.value = am.sfx_volume
	
	# Update labels
	_update_volume_label(master_label, "Master Volume", master_slider.value)
	_update_volume_label(music_label, "Music Volume", music_slider.value)
	_update_volume_label(sfx_label, "SFX Volume", sfx_slider.value)
	
	print("[Options] Settings loaded - Master: %.2f, Music: %.2f, SFX: %.2f" % [am.master_volume, am.music_volume, am.sfx_volume])
	
	# Force immediate application
	am.apply_volumes()

func _connect_signals() -> void:
	if master_slider:
		master_slider.value_changed.connect(_on_master_changed)
	if music_slider:
		music_slider.value_changed.connect(_on_music_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_changed)
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)

func _on_master_changed(value: float) -> void:
	var am := _get_audio_manager()
	if am:
		am.set_master_volume(value)
		_update_volume_label(master_label, "Master Volume", value)
		print("[Options] Master volume changed to: %.2f" % value)

func _on_music_changed(value: float) -> void:
	var am := _get_audio_manager()
	if am:
		am.set_music_volume(value)
		_update_volume_label(music_label, "Music Volume", value)
		print("[Options] Music volume changed to: %.2f" % value)

func _on_sfx_changed(value: float) -> void:
	var am := _get_audio_manager()
	if am:
		am.set_sfx_volume(value)
		_update_volume_label(sfx_label, "SFX Volume", value)
		print("[Options] SFX volume changed to: %.2f" % value)


func _update_volume_label(label: Label, base_text: String, value: float) -> void:
	if label:
		var percentage := int(value * 100)
		label.text = base_text + ": " + str(percentage) + "%"

func _on_back_pressed() -> void:
	var am := _get_audio_manager()
	var back_to := ""
	
	if am and "return_path" in am:
		back_to = String(am.return_path)
		
	if back_to != "" and ResourceLoader.exists(back_to):
		print("[Options] Returning to: " + back_to)
		get_tree().change_scene_to_file(back_to)
		return
		
	# Fallback to main menu
	var menu := "res://scenes/main_menu.tscn"
	if ResourceLoader.exists(menu):
		print("[Options] Returning to main menu")
		get_tree().change_scene_to_file(menu)

func _get_audio_manager() -> Node:
	var am := get_node_or_null("/root/AudioManager")
	if not am:
		print("[Options] AudioManager singleton not found at /root/AudioManager")
	return am

func _apply_current_volumes() -> void:
	var am := _get_audio_manager()
	if am:
		print("[Options] AudioManager found - applying current volumes")
		if am.has_method("apply_volumes"):
			am.apply_volumes()
		# Force immediate application of current slider values
		if master_slider:
			am.set_master_volume(master_slider.value)
		if music_slider:
			am.set_music_volume(music_slider.value)
		if sfx_slider:
			am.set_sfx_volume(sfx_slider.value)
		print("[Options] All volumes applied successfully")
	else:
		print("[Options] WARNING: AudioManager not available - audio controls will not work")
		print("[Options] Make sure to add AudioManager as AutoLoad in Project Settings")
