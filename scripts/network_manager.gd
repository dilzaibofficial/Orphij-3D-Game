extends Node
## Thin wrapper around Godot's built-in ENet multiplayer for LAN play,
## plus a small UDP broadcast discovery protocol so joining a
## friend's game means picking it from a list -- no IP address to
## type, no code to relay through a server. Autoloaded as "Network".
## No external service, no cost.

const PORT := 8910
const DISCOVERY_PORT := 8911
const MAX_PLAYERS := 20
const BROADCAST_INTERVAL := 1.0
const HOST_TIMEOUT := 3.5 # drop a discovered game if it stops broadcasting

signal server_started()
signal connected_to_server()
signal connection_failed()
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal discovered_games_changed()

var is_networked := false
var is_host := false
var hosting_code := ""

var _broadcast_socket: PacketPeerUDP
var _listen_socket: PacketPeerUDP
var _broadcast_timer := 0.0
var _hosting_name := ""

# ip -> {"name": String, "code": String, "last_seen": int (msec)}
var _discovered := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(host_name: String) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_networked = true
	is_host = true
	hosting_code = _generate_room_code()
	_start_broadcasting(host_name)
	server_started.emit()
	return OK


const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # no O/0/I/1, easy to read aloud

func _generate_room_code() -> String:
	var code := ""
	for i in range(4):
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code


## Looks up a currently-discovered game by its room code (case/space
## insensitive). Returns the host's IP, or "" if no match is live
## right now -- the code is just a friendlier stand-in for "pick the
## right discovered game," not a server-side lookup.
func find_ip_for_code(code: String) -> String:
	var wanted := code.strip_edges().to_upper()
	for ip in _discovered:
		if String(_discovered[ip].get("code", "")) == wanted:
			return ip
	return ""


func join_game(ip_address: String) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_networked = true
	is_host = false
	stop_discovery()
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_networked = false
	is_host = false
	_stop_broadcasting()


## Once connected, the host calls this to send every peer (including
## itself) to the same scene at the same time -- e.g. Lobby -> the
## actual match, once everyone's ready.
func start_game_for_everyone(scene_path: String) -> void:
	rpc(&"_rpc_change_scene", scene_path)


@rpc("authority", "call_local", "reliable")
func _rpc_change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


## Best-effort LAN IPv4 address, shown to the host mostly as a
## fallback/manual option -- discovery is the primary join path.
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


# ---------------------------------------------------------- discovery

func start_discovery() -> void:
	if _listen_socket:
		return
	_listen_socket = PacketPeerUDP.new()
	var err := _listen_socket.bind(DISCOVERY_PORT)
	if err != OK:
		push_error("Network: could not listen for LAN games (error %d)." % err)
		_listen_socket = null
	_discovered.clear()


func stop_discovery() -> void:
	if _listen_socket:
		_listen_socket.close()
	_listen_socket = null
	_discovered.clear()


## {ip: {"name": String, "code": String}} of currently-live discovered games.
func get_discovered_games() -> Dictionary:
	var result := {}
	for ip in _discovered:
		result[ip] = {"name": _discovered[ip]["name"], "code": _discovered[ip]["code"]}
	return result


func _start_broadcasting(host_name: String) -> void:
	_hosting_name = host_name
	_broadcast_socket = PacketPeerUDP.new()
	_broadcast_socket.set_broadcast_enabled(true)
	_broadcast_timer = 0.0


func _stop_broadcasting() -> void:
	_broadcast_socket = null


func _process(delta: float) -> void:
	if _broadcast_socket:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			var payload := JSON.stringify({"name": _hosting_name, "code": hosting_code})
			_broadcast_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_broadcast_socket.put_packet(payload.to_utf8_buffer())

	if _listen_socket:
		var changed := false
		while _listen_socket.get_available_packet_count() > 0:
			var packet := _listen_socket.get_packet()
			var sender_ip := _listen_socket.get_packet_ip()
			var data = JSON.parse_string(packet.get_string_from_utf8())
			if data and typeof(data) == TYPE_DICTIONARY:
				_discovered[sender_ip] = {
					"name": data.get("name", "Game"),
					"code": data.get("code", "----"),
					"last_seen": Time.get_ticks_msec(),
				}
				changed = true

		var now := Time.get_ticks_msec()
		for ip in _discovered.keys():
			if now - _discovered[ip]["last_seen"] > HOST_TIMEOUT * 1000:
				_discovered.erase(ip)
				changed = true

		if changed:
			discovered_games_changed.emit()


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	is_networked = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	is_networked = false
	connection_failed.emit()
