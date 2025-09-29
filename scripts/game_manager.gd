extends Node

signal game_over()
signal score_changed(new_score: int)
signal can_hit()

@export var game_scene: PackedScene

var score: int = 0
var game_active: bool = true
var ui_manager: Node = null

func _is_networked() -> bool:
	# get_tree() can be null during teardown or very early lifecycle
	var tree := get_tree()
	if tree == null:
		return false
	var tree_mp := tree.get_multiplayer()
	return tree_mp != null and tree_mp.multiplayer_peer != null



func _ready() -> void:
	# Connect to slipper signals
	_connect_slipper_signals()
	
	# Connect to defender AI (offline only). In LAN we do not use AI.
	if get_tree().get_multiplayer() == null or get_tree().get_multiplayer().multiplayer_peer == null:
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
	if not multiplayer.is_server():
		return
	if not game_active:
		return
	
	game_active = false
	emit_signal("game_over")
	
	# Show game over UI
	if ui_manager and ui_manager.has_method("show_game_over"):
		ui_manager.show_game_over()
	if _is_networked():
		rpc("_rpc_sync_game_over", score)

func add_score(points: int) -> void:
	# Allow offline scoring; in networked sessions only server scores
	if _is_networked() and not multiplayer.is_server():
		return
	if not game_active:
		return
	
	score += points
	emit_signal("score_changed", score)
	emit_signal("can_hit")
	# Local-only: give a small camera shake on can hits
	if not _is_networked():
		_call_deferred_shake()
	if _is_networked():
		rpc("_rpc_sync_score", score)

func restart_game() -> void:
	# In networked mode, only server performs restart; offline proceeds locally
	if _is_networked() and not multiplayer.is_server():
		rpc_id(1, "_rpc_request_restart")
		return
	
	_apply_restart_state()
	# Ask world to reset round positions/state immediately
	var world := get_tree().current_scene
	if world and world.has_method("_reset_round"):
		world._reset_round()
	# In offline mode, prefer an in-place reset; if you still want a reload, do it deferred
	if not _is_networked():
		if game_scene != null:
			call_deferred("_deferred_change_scene_packed")
		else:
			# Fallback: reload current scene by path
			var path := get_tree().current_scene.scene_file_path
			if path != "" and ResourceLoader.exists(path):
				call_deferred("_deferred_change_scene_path", path)
	if _is_networked():
		rpc("_rpc_sync_restart")

func _apply_restart_state() -> void:
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

func _deferred_change_scene_packed() -> void:
	if game_scene != null:
		get_tree().change_scene_to_packed(game_scene)

func _deferred_change_scene_path(path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)

func _call_deferred_shake() -> void:
	call_deferred("_shake_camera", 6.0, 0.25)

func _shake_camera(intensity: float = 6.0, duration: float = 0.25) -> void:
	# Find the active camera in the scene
	var cam: Camera2D = null
	var viewport := get_viewport()
	if viewport:
		cam = viewport.get_camera_2d()
	
	# Fallback: search for any Camera2D in the scene tree
	if cam == null:
		var root := get_tree().current_scene
		if root:
			cam = _find_camera_recursive(root)
	
	if cam == null:
		print("[GameManager] No Camera2D found for screen shake")
		return
		
	var original_offset: Vector2 = cam.offset
	var steps: int = max(1, int(ceil(duration / 0.04)))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(steps):
		var shake_amount := intensity * (1.0 - float(i) / float(steps))  # Decay over time
		cam.offset = original_offset + Vector2(
			rng.randf_range(-shake_amount, shake_amount),
			rng.randf_range(-shake_amount, shake_amount)
		)
		await get_tree().create_timer(0.04).timeout
	
	cam.offset = original_offset

func _find_camera_recursive(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
	for child in node.get_children():
		var result := _find_camera_recursive(child)
		if result:
			return result
	return null

func set_ui_manager(ui: Node) -> void:
	ui_manager = ui

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_score(new_score: int) -> void:
	score = new_score
	emit_signal("score_changed", score)
	emit_signal("can_hit")

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_game_over(final_score: int) -> void:
	game_active = false
	score = final_score
	emit_signal("score_changed", score)
	emit_signal("game_over")
	if ui_manager and ui_manager.has_method("show_game_over"):
		ui_manager.show_game_over()

@rpc("any_peer", "call_local", "reliable")
func _rpc_request_restart() -> void:
	if not multiplayer.is_server():
		return
	restart_game()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_restart() -> void:
	_apply_restart_state()
