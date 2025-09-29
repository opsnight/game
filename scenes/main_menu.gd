extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Ensure main menu music routes to the Music bus so Options can control it
	var ap: AudioStreamPlayer = $AudioStreamPlayer
	if ap:
		ap.bus = "Music"
		# Start music through AudioManager so it persists across scenes
		var am := _am()
		if am:
			if am.has_method("apply_volumes"):
				am.apply_volumes()
			if am.has_method("play_music") and ap.stream:
				am.play_music(ap.stream, true)
			# Prevent the local node from also playing
			ap.autoplay = false
			if ap.playing:
				ap.stop()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_startgame_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_selection.tscn")


func _on_option_pressed() -> void:
	# Remember current scene to return after options
	var am := _am()
	if am:
		var cur := get_tree().current_scene
		if cur and cur.scene_file_path != "":
			am.return_path = cur.scene_file_path
	# Go to options scene if present
	var opt := "res://scenes/option.tscn"
	if ResourceLoader.exists(opt):
		get_tree().change_scene_to_file(opt)


func _on_quit_pressed() -> void:
	get_tree().quit()

func _am() -> Node:
	return get_node_or_null("/root/AudioManager")
