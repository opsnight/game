extends Node2D

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var synchronizer: MultiplayerSynchronizer = $Synchronizer
@onready var spawn_point: Node2D = $SpawnPoint

@onready var ip_input: LineEdit = $UI/MainContainer/VBox/IPInput
@onready var host_button: Button = $UI/MainContainer/VBox/HBoxButtons/HostButton
@onready var join_button: Button = $UI/MainContainer/VBox/HBoxButtons/JoinButton
@onready var start_button: Button = $UI/MainContainer/VBox/StartGameButton
@onready var status_label: Label = $UI/MainContainer/VBox/StatusLabel
@onready var players_list: ItemList = $UI/MainContainer/VBox/PlayersList
var back_button: Button

var is_server: bool = false

func _ready() -> void:
	# Prepare spawner for later gameplay scene usage
	if spawner:
		spawner.spawn_path = NodePath(".")
		spawner.spawn_limit = 10
		# Register the networked player scene for replication
		if ResourceLoader.exists("res://scenes/networked_player.tscn"):
			spawner.add_spawnable_scene("res://scenes/networked_player.tscn")
	
	# Hook up UI
	if host_button: host_button.pressed.connect(_on_host)
	if join_button: join_button.pressed.connect(_on_join)
	if start_button: start_button.pressed.connect(_on_start_game)
	# Resolve Back button (supports multiple layouts and cases)
	back_button = _resolve_back_button()
	if back_button:
		back_button.disabled = false
		back_button.mouse_filter = Control.MOUSE_FILTER_STOP
		back_button.focus_mode = Control.FOCUS_ALL
		back_button.pressed.connect(_on_back)
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Show a helpful default IP
	_update_status("Idle. Enter IP and Host/Join.")
	_refresh_players()

func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		_update_status("Failed to create server: %s" % [err])
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	start_button.disabled = false
	_update_status("Server started on %s:%d" % [_get_local_ip(), DEFAULT_PORT])
	_refresh_players()

func _on_join() -> void:
	var host_ip := ip_input.text.strip_edges()
	if host_ip.is_empty():
		_update_status("Please enter host IP")
		return
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_client(host_ip, DEFAULT_PORT)
	if err != OK:
		_update_status("Failed to connect: %s" % [err])
		return
	multiplayer.multiplayer_peer = peer
	is_server = false
	start_button.disabled = true
	_update_status("Connecting to %s:%d ..." % [host_ip, DEFAULT_PORT])

func _on_start_game() -> void:
	if not multiplayer.is_server():
		_update_status("Only server can start the game.")
		return
	# Role assignment logic: if exactly 2 players, server=attacker, client=defender
	# If more than 2, randomize roles: 1 defender, up to 5 throwers
	var all_ids: Array = [1]
	for p in multiplayer.get_peers():
		all_ids.append(p)

	var roles: Dictionary = {}
	if all_ids.size() == 2:
		# Exactly 2 players: server is attacker, client is defender
		roles[1] = "thrower"  # Server (peer 1)
		roles[all_ids[1]] = "defender"  # First client
	else:
		# More than 2 players: randomize roles
		all_ids.shuffle()
		if all_ids.size() > 0:
			roles[all_ids[0]] = "defender"
		# All remaining peers are attackers
		for i in range(1, all_ids.size()):
			roles[all_ids[i]] = "thrower"

	# Save roles locally and broadcast to clients
	if Engine.has_singleton("GameConfig"):
		GameConfig.clear_roles()
		GameConfig.roles = roles
	rpc("_rpc_set_roles", roles)
	# Start game for everyone
	rpc("_rpc_begin_game")

func _on_back() -> void:
	_cleanup_network()
	# Return to previous section (game selection screen)
	var game_sel := "res://scenes/game_selection.tscn"
	if ResourceLoader.exists(game_sel):
		get_tree().change_scene_to_file(game_sel)
	else:
		var menu := "res://scenes/main_menu.tscn"
		if ResourceLoader.exists(menu):
			get_tree().change_scene_to_file(menu)

func _cleanup_network() -> void:
	# Close any active ENet connection and clear roles/state
	if multiplayer and multiplayer.multiplayer_peer != null:
		var peer := multiplayer.multiplayer_peer
		if peer and peer.has_method("close"):
			peer.close()
		multiplayer.multiplayer_peer = null
	# Clear roles to avoid stale state next time
	if Engine.has_singleton("GameConfig"):
		if GameConfig.has_method("clear_roles"):
			GameConfig.clear_roles()

func _resolve_back_button() -> Button:
	# Try exact path provided by user (case-sensitive): Multiplayerlobby/UI/background/backbutton
	var candidates := [
		"UI/background/Back Button",
		"UI/Background/Back Button",
		"UI/Background/BackButton",
		"UI/MainContainer/VBox/HBoxButtons/BackButton",
		"Multiplayerlobby/UI/background/Back Button",
		"Multiplayerlobby/UI/background/backbutton",
		"MultiplayerLobby/UI/background/Back Button",
		"MultiplayerLobby/UI/background/backbutton",
		"MultiplayerLobby/UI/background/BackButton"
	]
	for p in candidates:
		if has_node(p):
			var n := get_node(p)
			if n is Button:
				return n
	# As a last resort, search under UI for any node named 'backbutton' or 'back button' (case-insensitive)
	var ui := get_node_or_null("UI")
	if ui:
		var stack: Array = [ui]
		while stack.size() > 0:
			var cur: Node = stack.pop_back()
			for child in cur.get_children():
				if child is Button:
					var nm := String(child.name).to_lower()
					if nm == "backbutton" or nm == "back button":
						return child
				stack.append(child)
	return null

@rpc("any_peer", "call_local", "reliable")
func _rpc_begin_game() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_roles(new_roles: Dictionary) -> void:
		GameConfig.clear_roles()
		GameConfig.roles = new_roles.duplicate(true)
func _on_peer_connected(id: int) -> void:
	_refresh_players()
	if multiplayer.is_server():
		_update_status("Peer connected: %d" % id)
		# Broadcast roles to all peers
		rpc("_rpc_set_roles", GameConfig.roles)
func _on_peer_disconnected(id: int) -> void:
	_refresh_players()
	_update_status("Peer disconnected: %d" % id)

func _on_connection_failed() -> void:
	_update_status("Connection failed.")

func _on_server_disconnected() -> void:
	_update_status("Disconnected from server.")

func _refresh_players() -> void:
	if players_list == null:
		return
	players_list.clear()
	if multiplayer.multiplayer_peer == null:
		return
	var peers := multiplayer.get_peers()
	peers.sort()
	# Add server first
	players_list.add_item("Server (ID 1)")
	for p in peers:
		if p == 1:
			continue
		players_list.add_item("Peer %d" % p)

func _update_status(t: String) -> void:
	if status_label:
		status_label.text = "Status: %s" % t

func _get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for a in addresses:
		if a.begins_with("192.168.") and _is_valid_ipv4(a):
			return a
	for a in addresses:
		if a.begins_with("10.") and _is_valid_ipv4(a):
			return a
	return "127.0.0.1"

func _is_valid_ipv4(ip: String) -> bool:
	if ip.contains(":"):
		return false
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
		var n := int(part)
		if n < 0 or n > 255:
			return false
	return true

func _on_back1_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_selection.tscn")
