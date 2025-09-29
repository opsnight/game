extends Node

# Global Audio Manager (add as AutoLoad: Project Settings -> AutoLoad -> audio_manager.gd as "AudioManager")
# Provides:
# - Master/Music/SFX volume control with persistence (user://settings.cfg)
# - Ensures "Music" and "SFX" buses exist and route to Master
# - Simple helpers to play music and SFX

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0

# Optional: path to return to from options
var return_path: String = ""

const CONFIG_PATH := "user://settings.cfg"

var _music_player: AudioStreamPlayer
var _music_should_loop: bool = true
var _current_music_stream: AudioStream = null
var stop_on_scene_change: bool = false

func _ready() -> void:
	print("[AudioManager] Initializing AudioManager...")
	_ensure_buses()
	_load_settings()
	apply_volumes()
	print("[AudioManager] AudioManager ready - Master: %.2f, Music: %.2f, SFX: %.2f" % [master_volume, music_volume, sfx_volume])

func apply_volumes() -> void:
	print("[AudioManager] Applying volumes - Master: %.2f, Music: %.2f, SFX: %.2f" % [master_volume, music_volume, sfx_volume])
	_set_bus_lin("Master", 0, master_volume)
	_set_named_bus_lin(["Music", "BGM", "music", "bgm"], music_volume)
	_set_named_bus_lin(["SFX", "Sfx", "Effects", "effects", "FX", "fx", "UI"], sfx_volume)
	
	# Also apply to any existing AudioStreamPlayers in the scene tree
	_apply_to_existing_players()
	print("[AudioManager] Volume application complete")

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	print("[AudioManager] Setting master volume to: %.2f" % master_volume)
	_set_bus_lin("Master", 0, master_volume)
	_apply_to_existing_players()
	_save_settings()

func set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	print("[AudioManager] Setting music volume to: %.2f" % music_volume)
	_set_named_bus_lin(["Music", "BGM", "music", "bgm"], music_volume)
	_apply_to_existing_players()
	_save_settings()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	print("[AudioManager] Setting SFX volume to: %.2f" % sfx_volume)
	_set_named_bus_lin(["SFX", "Sfx", "Effects", "effects", "FX", "fx", "UI"], sfx_volume)
	_apply_to_existing_players()
	_save_settings()

# --- Music/SFX helpers ---
func play_music(stream: AudioStream, loop: bool = true) -> void:
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		_music_player.bus = _get_or_create_bus("Music")
		add_child(_music_player)
	# If same stream is already playing, don't restart to keep it seamless
	if _music_player.playing and _current_music_stream == stream:
		return
	_music_player.stream = stream
	_current_music_stream = stream
	_music_player.autoplay = false
	_music_should_loop = loop
	if not _music_player.finished.is_connected(_on_music_finished):
		_music_player.finished.connect(_on_music_finished)
	_music_player.play()

func stop_music() -> void:
	if _music_player:
		_music_player.stop()
		_music_should_loop = false

func play_sfx(stream: AudioStream, volume_db_offset: float = 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = _get_or_create_bus("SFX")
	p.stream = stream
	add_child(p)
	p.volume_db += volume_db_offset
	p.finished.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)
	p.play()

func play_test_sfx() -> void:
	# Create a simple test tone programmatically
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.1
	
	var player := AudioStreamPlayer.new()
	player.bus = _get_or_create_bus("SFX")
	player.stream = generator
	add_child(player)
	
	player.finished.connect(func():
		if is_instance_valid(player):
			player.queue_free()
	)
	
	player.play()
	
	# Stop after short duration
	get_tree().create_timer(0.2).timeout.connect(func():
		if is_instance_valid(player):
			player.stop()
	)

func _on_music_finished() -> void:
	if _music_should_loop and _music_player and _music_player.stream:
		_music_player.play()

# --- Internals ---
func _ensure_buses() -> void:
	_get_or_create_bus("Music")
	_get_or_create_bus("SFX")

func _get_or_create_bus(name: String) -> String:
	var idx := AudioServer.get_bus_index(name)
	if idx == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	return name

func _set_named_bus_lin(names: Array, value: float) -> void:
	for n in names:
		var idx := AudioServer.get_bus_index(n)
		if idx != -1:
			_set_bus_lin(n, idx, value)
			return

func _set_bus_lin(name: String, idx: int, value: float) -> void:
	var v: float = clamp(value, 0.0, 1.0)
	var db: float = linear_to_db(max(0.0001, v))
	if idx < 0:
		idx = AudioServer.get_bus_index(name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, v <= 0.0001)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		master_volume = float(cfg.get_value("audio", "master", master_volume))
		music_volume = float(cfg.get_value("audio", "music", music_volume))
		sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))

func _apply_to_existing_players() -> void:
	# Find all AudioStreamPlayers in the scene tree and ensure they use correct buses
	var root := get_tree().current_scene
	if not root:
		return
		
	var players: Array = _find_all_audio_players(root)
	print("[AudioManager] Found %d audio players to update" % players.size())
	
	for player in players:
		if player is AudioStreamPlayer or player is AudioStreamPlayer2D or player is AudioStreamPlayer3D:
			# Auto-assign buses based on common naming patterns
			var player_name: String = String(player.name).to_lower()
			var current_bus: String = String(player.bus)
			
			# If no bus assigned or on Master, try to categorize
			if current_bus == "Master" or current_bus == "":
				if "music" in player_name or "bgm" in player_name or "background" in player_name:
					player.bus = "Music"
					print("[AudioManager] Assigned %s to Music bus" % player.name)
				elif "sfx" in player_name or "sound" in player_name or "effect" in player_name:
					player.bus = "SFX"
					print("[AudioManager] Assigned %s to SFX bus" % player.name)
				else:
					# Main menu music and other background audio
					if player.autoplay or player.playing:
						player.bus = "Music"
						print("[AudioManager] Assigned playing audio %s to Music bus" % player.name)

func _find_all_audio_players(node: Node) -> Array:
	var players: Array = []
	
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		players.append(node)
	
	for child in node.get_children():
		players.append_array(_find_all_audio_players(child))
	
	return players

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	var result: int = cfg.save(CONFIG_PATH)
	if result == OK:
		print("[AudioManager] Settings saved successfully to %s" % CONFIG_PATH)
	else:
		print("[AudioManager] Failed to save settings: %d" % result)
