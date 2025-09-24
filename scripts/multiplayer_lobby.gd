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
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Show a helpful default IP
	ip_input.text = _get_local_ip()
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
	# Tell everyone to switch to the gameplay scene
	rpc("_rpc_begin_game")

@rpc("any_peer", "call_local", "reliable")
func _rpc_begin_game() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_peer_connected(id: int) -> void:
	_refresh_players()
	if multiplayer.is_server():
		_update_status("Peer connected: %d" % id)

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
