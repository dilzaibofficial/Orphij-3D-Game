extends Node3D
## Lobby: a small room with three ways in -- Solo (unchanged, no
## networking at all), Host (starts a LAN game and broadcasts it so
## friends can find it), or Join (pick a discovered game from a
## live list, no IP address to type). Once host+friends are
## connected, everyone stands here as real networked characters
## (not decorative NPCs) until the host presses Start, which sends
## everyone into the match together via Network.start_game_for_everyone().

const ROOM_SIZE := 26.0
const WALL_HEIGHT := 9.0
const SPAWN_POS := Vector3(0, 2, 9)

const HEADING_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"
const COLOR_GOLD := Color(0xCA / 255.0, 0x8A / 255.0, 0x04 / 255.0)
const COLOR_GREEN := Color(0x22 / 255.0, 0xC5 / 255.0, 0x5E / 255.0)
const COLOR_RED := Color(0xEF / 255.0, 0x44 / 255.0, 0x44 / 255.0)
const COLOR_TEXT := Color(0xF8 / 255.0, 0xFA / 255.0, 0xFC / 255.0)

@export var target_game_scene := "res://scenes/games/RedLightGreenLight.tscn"

var heading_font: FontFile
var mode := "menu" # "menu", "solo", "networked"

var player_container: Node3D
var spawner: MultiplayerSpawner
var players := {} # peer_id -> CharacterBody3D
var player: CharacterBody3D

var menu_panel: Control
var room_panel: Control
var solo_panel: Control
var solo_prompt: Label
var discovery_list: VBoxContainer
var code_field: LineEdit
var manual_ip_row: HBoxContainer
var manual_ip_field: LineEdit
var menu_status_label: Label
var room_status_label: Label
var room_code_label: Label
var player_list_label: Label
var start_button: Button
var leave_button: Button
var solo_menu_button: Button
var solo_back_button: Button
var customize_close_button: Button
var customize_panel: Control
var pending_customization := {}
var swatch_buttons := {} # part -> Array[Button]


func _ready() -> void:
	WorldBuilder.build_sky_environment(self)
	WorldBuilder.build_sun(self)
	WorldBuilder.build_ground(self, ROOM_SIZE, Color(0.55, 0.5, 0.45))
	WorldBuilder.build_walls(self, ROOM_SIZE, WALL_HEIGHT, 1.5, Color(0.68, 0.65, 0.6))
	heading_font = load(HEADING_FONT)
	_setup_ui()

	Network.connected_to_server.connect(_on_connected_to_server)
	Network.connection_failed.connect(_on_connection_failed)
	Network.discovered_games_changed.connect(_refresh_discovery_list)
	Network.player_connected.connect(_on_network_player_connected)
	Network.player_disconnected.connect(_on_network_player_disconnected)

	Network.start_discovery()
	_refresh_discovery_list()

	# Gamepad D-pad/left-stick + Cross (Godot's default ui_up/down/
	# left/right/accept, already bound to joypad out of the box) needs
	# an initial focus target to start navigating from.
	solo_menu_button.grab_focus()


func _process(_delta: float) -> void:
	if mode == "solo" and (Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_key_pressed(KEY_SPACE)):
		get_tree().change_scene_to_file(target_game_scene)


# ------------------------------------------------------------- entry modes

func _on_solo_pressed() -> void:
	mode = "solo"
	Network.stop_discovery()
	menu_panel.visible = false
	player = WorldBuilder.spawn_player(self, SPAWN_POS)
	player.username = Auth.username if not Auth.username.is_empty() else "Player"
	WorldBuilder.apply_customization(player)
	solo_panel.visible = true
	solo_back_button.grab_focus()


func _on_host_pressed() -> void:
	var host_name: String = Auth.username if not Auth.username.is_empty() else "Player"
	var err: int = Network.host_game(host_name)
	if err != OK:
		_set_status(menu_status_label, "Could not start hosting (error %d)." % err, COLOR_RED)
		return
	Network.stop_discovery()
	_enter_networked_room()


func _on_join_selected(ip: String) -> void:
	_set_status(menu_status_label, "Connecting...", COLOR_TEXT)
	var err: int = Network.join_game(ip)
	if err != OK:
		_set_status(menu_status_label, "Could not connect (error %d)." % err, COLOR_RED)


func _on_join_by_code_pressed() -> void:
	var code := code_field.text.strip_edges()
	if code.is_empty():
		_set_status(menu_status_label, "Enter the code your friend gave you.", COLOR_RED)
		return
	var ip := Network.find_ip_for_code(code)
	if ip.is_empty():
		_set_status(menu_status_label, "No game found with that code. Make sure you're both on the same WiFi.", COLOR_RED)
		return
	_on_join_selected(ip)


func _on_connected_to_server() -> void:
	_enter_networked_room()


func _on_connection_failed() -> void:
	_set_status(menu_status_label, "Connection failed. Make sure you're on the same WiFi.", COLOR_RED)


func _enter_networked_room() -> void:
	mode = "networked"
	menu_panel.visible = false
	room_panel.visible = true
	start_button.visible = Network.is_host
	room_code_label.visible = Network.is_host
	if Network.is_host:
		room_code_label.text = "ROOM CODE:  " + Network.hosting_code
		room_status_label.text = "Tell friends this code to join you."
	else:
		room_status_label.text = "Connected! Waiting for the host to start..."
	room_status_label.label_settings.font_color = COLOR_GREEN
	_setup_networked_players()
	if Network.is_host:
		start_button.grab_focus()
	else:
		leave_button.grab_focus()


func _on_start_game_pressed() -> void:
	Network.start_game_for_everyone(target_game_scene)


# --------------------------------------------------------- networked room

func _setup_networked_players() -> void:
	player_container = Node3D.new()
	player_container.name = "Players"
	add_child(player_container)

	spawner = MultiplayerSpawner.new()
	# Multiplayer replication identifies nodes by path, including
	# this one's own name -- an auto-generated "@MultiplayerSpawner@N"
	# name can end up numbered differently on the host vs. a client
	# (they don't create the exact same anonymous nodes in the exact
	# same order beforehand), which breaks spawn replication. A fixed
	# name keeps it identical on every peer.
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	spawner.spawn_path = player_container.get_path()
	spawner.spawn_function = _create_networked_player

	if Network.is_host:
		_request_spawn(1)


func _on_network_player_connected(peer_id: int) -> void:
	if Network.is_host:
		_request_spawn(peer_id)


func _on_network_player_disconnected(peer_id: int) -> void:
	if players.has(peer_id):
		var p = players[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(peer_id)
	_update_player_list_label()


func _request_spawn(peer_id: int) -> void:
	if players.has(peer_id):
		return
	spawner.spawn(peer_id)


## Runs on every peer (the caller's spawn() replicates to all of
## them), so everyone ends up with an identical, correctly-authorized
## instance -- same pattern as the game scene's player spawning.
func _create_networked_player(peer_id: int) -> CharacterBody3D:
	var player_scene: PackedScene = load(WorldBuilder.PLAYER_SCENE)
	var new_player: CharacterBody3D = player_scene.instantiate()
	new_player.name = "Player_%d" % peer_id
	new_player.position = SPAWN_POS + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	new_player.set_multiplayer_authority(peer_id)
	players[peer_id] = new_player
	if peer_id == multiplayer.get_unique_id():
		player = new_player
		new_player.username = Auth.username if not Auth.username.is_empty() else "Player"
		WorldBuilder.apply_customization(new_player)
	call_deferred("_update_player_list_label")
	return new_player


func _update_player_list_label() -> void:
	if player_list_label == null:
		return
	var names: Array[String] = []
	for p in players.values():
		if is_instance_valid(p):
			names.append(p.username if not p.username.is_empty() else "Player")
	player_list_label.text = "Players (%d): %s" % [names.size(), ", ".join(names)]


# ------------------------------------------------------------------- UI

func _make_label_settings(size: int, color: Color, use_heading: bool = true) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	if use_heading and heading_font:
		settings.font = heading_font
	settings.outline_size = 8
	settings.outline_color = Color(0.05, 0.05, 0.08, 0.9)
	settings.shadow_size = 4
	settings.shadow_color = Color(0, 0, 0, 0.5)
	return settings


func _make_panel(size: Vector2) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0x1B / 255.0, 0x1B / 255.0, 0x30 / 255.0, 0.9)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = size
	panel.size = size
	return panel


func _setup_ui() -> void:
	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)

	var root_control := Control.new()
	root_control.theme = UITheme.build()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(root_control)

	_setup_menu_panel(root_control)
	_setup_room_panel(root_control)
	_setup_solo_prompt(root_control)
	_setup_customize_button(root_control)
	_setup_customize_panel(root_control)


const SKIN_TONES := [
	Color8(255, 219, 172), Color8(241, 194, 125), Color8(224, 172, 105),
	Color8(198, 134, 66), Color8(141, 85, 36), Color8(92, 58, 33),
]
const HAIR_COLORS := [
	Color8(26, 19, 16), Color8(74, 44, 23), Color8(212, 166, 58),
	Color8(163, 60, 30), Color8(107, 107, 107), Color8(232, 224, 208),
]
const SHIRT_COLORS := [
	Color8(240, 204, 38), Color8(220, 50, 50), Color8(50, 110, 220),
	Color8(50, 180, 90), Color8(150, 60, 200), Color8(30, 30, 30),
]
const PANTS_COLORS := [
	Color8(60, 70, 110), Color8(30, 30, 30), Color8(150, 130, 90),
	Color8(90, 90, 90), Color8(80, 55, 30), Color8(40, 70, 40),
]


func _setup_customize_button(root_control: Control) -> void:
	var button := Button.new()
	button.text = "✎  Customize"
	button.custom_minimum_size = Vector2(160, 44)
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.position = Vector2(20, 20)
	button.pressed.connect(_open_customize_panel)
	root_control.add_child(button)


func _open_customize_panel() -> void:
	pending_customization = Auth.customization.duplicate()
	customize_panel.visible = true
	_refresh_swatch_selection()
	customize_close_button.grab_focus()


func _close_customize_panel(save: bool) -> void:
	if save:
		for part in pending_customization:
			Auth.set_customization_color(part, pending_customization[part])
	elif player:
		# Cancelled -- put the live preview back to what's actually saved.
		WorldBuilder.apply_customization(player)
	customize_panel.visible = false


func _setup_customize_panel(root_control: Control) -> void:
	customize_panel = Control.new()
	customize_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	customize_panel.visible = false
	root_control.add_child(customize_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	customize_panel.add_child(dim)

	var panel := _make_panel(Vector2(500, 560))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-250, -280)
	customize_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "CUSTOMIZE YOUR CHARACTER"
	title.label_settings = _make_label_settings(24, COLOR_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	customize_close_button = Button.new()
	var close_x := customize_close_button
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(36, 36)
	close_x.flat = true
	close_x.pressed.connect(_close_customize_panel.bind(false))
	header.add_child(close_x)

	var subtitle := Label.new()
	subtitle.text = "Look behind the panel -- your character updates live as you pick. Nothing is saved until you press Done."
	subtitle.label_settings = _make_label_settings(13, COLOR_TEXT, false)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	swatch_buttons.clear()
	vbox.add_child(_make_swatch_row("skin", "Skin Tone", SKIN_TONES))
	vbox.add_child(_make_swatch_row("hair", "Hair Color", HAIR_COLORS))
	vbox.add_child(_make_swatch_row("shirt", "Shirt Color", SHIRT_COLORS))
	vbox.add_child(_make_swatch_row("pants", "Pants Color", PANTS_COLORS))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	var cancel_button := Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.custom_minimum_size = Vector2(0, 46)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(_close_customize_panel.bind(false))
	button_row.add_child(cancel_button)

	var done_button := Button.new()
	done_button.text = "DONE"
	done_button.custom_minimum_size = Vector2(0, 46)
	done_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_button.pressed.connect(_close_customize_panel.bind(true))
	button_row.add_child(done_button)


func _make_swatch_row(part: String, label_text: String, colors: Array) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.label_settings = _make_label_settings(15, COLOR_TEXT, false)
	section.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	section.add_child(row)

	swatch_buttons[part] = []
	for color in colors:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.set_meta("color", color)
		swatch.pressed.connect(_on_swatch_selected.bind(part, color))
		row.add_child(swatch)
		swatch_buttons[part].append(swatch)
		_style_swatch(swatch, color, false)

	return section


func _style_swatch(swatch: Button, color: Color, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.set_border_width_all(4 if selected else 1)
	style.border_color = COLOR_GOLD if selected else Color(1, 1, 1, 0.3)
	swatch.add_theme_stylebox_override("normal", style)
	swatch.add_theme_stylebox_override("hover", style)
	swatch.add_theme_stylebox_override("pressed", style)
	swatch.add_theme_stylebox_override("focus", style)


func _refresh_swatch_selection() -> void:
	for part in swatch_buttons:
		var current_hex: String = String(pending_customization.get(part, "")).to_upper()
		for swatch in swatch_buttons[part]:
			var color: Color = swatch.get_meta("color")
			var is_selected: bool = ("#" + color.to_html(false)).to_upper() == current_hex
			_style_swatch(swatch, color, is_selected)


func _on_swatch_selected(part: String, color: Color) -> void:
	pending_customization[part] = "#" + color.to_html(false)
	if player:
		player.set_outfit_color(part, color) # live preview only -- Auth isn't touched until Done
	_refresh_swatch_selection()


func _setup_menu_panel(root_control: Control) -> void:
	menu_panel = _make_panel(Vector2(420, 420))
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.position = Vector2(-210, -210)
	root_control.add_child(menu_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "ORPHIJ"
	title.label_settings = _make_label_settings(34, COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	solo_menu_button = Button.new()
	solo_menu_button.text = "PLAY SOLO"
	solo_menu_button.custom_minimum_size = Vector2(0, 42)
	solo_menu_button.pressed.connect(_on_solo_pressed)
	vbox.add_child(solo_menu_button)

	var host_button := Button.new()
	host_button.text = "HOST GAME"
	host_button.custom_minimum_size = Vector2(0, 42)
	host_button.pressed.connect(_on_host_pressed)
	vbox.add_child(host_button)

	var join_label := Label.new()
	join_label.text = "Got a friend's room code?"
	join_label.label_settings = _make_label_settings(13, COLOR_TEXT, false)
	vbox.add_child(join_label)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	vbox.add_child(code_row)

	code_field = LineEdit.new()
	code_field.placeholder_text = "CODE"
	code_field.max_length = 4
	code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_field.text_submitted.connect(func(_t): _on_join_by_code_pressed())
	code_row.add_child(code_field)

	var code_join_button := Button.new()
	code_join_button.text = "Join with Code"
	code_join_button.pressed.connect(_on_join_by_code_pressed)
	code_row.add_child(code_join_button)

	var or_label := Label.new()
	or_label.text = "or pick a game found on your WiFi:"
	or_label.label_settings = _make_label_settings(12, COLOR_TEXT, false)
	vbox.add_child(or_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(scroll)

	discovery_list = VBoxContainer.new()
	discovery_list.add_theme_constant_override("separation", 6)
	discovery_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(discovery_list)

	var manual_toggle := Button.new()
	manual_toggle.text = "Can't find it? Enter IP manually"
	manual_toggle.flat = true
	manual_toggle.add_theme_font_size_override("font_size", 12)
	manual_toggle.pressed.connect(func(): manual_ip_row.visible = not manual_ip_row.visible)
	vbox.add_child(manual_toggle)

	manual_ip_row = HBoxContainer.new()
	manual_ip_row.add_theme_constant_override("separation", 8)
	manual_ip_row.visible = false
	vbox.add_child(manual_ip_row)

	manual_ip_field = LineEdit.new()
	manual_ip_field.placeholder_text = "e.g. 192.168.1.5"
	manual_ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_ip_row.add_child(manual_ip_field)

	var manual_join_button := Button.new()
	manual_join_button.text = "Join"
	manual_join_button.pressed.connect(func(): _on_join_selected(manual_ip_field.text))
	manual_ip_row.add_child(manual_join_button)

	menu_status_label = Label.new()
	menu_status_label.label_settings = _make_label_settings(13, COLOR_TEXT, false)
	menu_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(menu_status_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	vbox.add_child(footer)

	var logout_button := Button.new()
	logout_button.text = "Log Out"
	logout_button.flat = true
	logout_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logout_button.pressed.connect(_on_logout_pressed)
	footer.add_child(logout_button)

	var quit_button := Button.new()
	quit_button.text = "Quit Game"
	quit_button.flat = true
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(func(): get_tree().quit())
	footer.add_child(quit_button)


func _on_logout_pressed() -> void:
	Network.disconnect_game()
	Auth.sign_out()
	get_tree().change_scene_to_file("res://scenes/Login.tscn")


func _refresh_discovery_list() -> void:
	for child in discovery_list.get_children():
		child.queue_free()

	var games := Network.get_discovered_games()
	if games.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Searching for games on your WiFi..."
		empty_label.label_settings = _make_label_settings(13, COLOR_TEXT, false)
		discovery_list.add_child(empty_label)
		return

	for ip in games:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = "%s's Game   [%s]" % [str(games[ip]["name"]), str(games[ip]["code"])]
		name_label.label_settings = _make_label_settings(14, COLOR_TEXT, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var join_button := Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(_on_join_selected.bind(ip))
		row.add_child(join_button)

		discovery_list.add_child(row)


func _setup_room_panel(root_control: Control) -> void:
	room_panel = _make_panel(Vector2(420, 220))
	room_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	room_panel.anchor_left = 0.5
	room_panel.anchor_right = 0.5
	room_panel.position = Vector2(-210, 20)
	room_panel.visible = false
	root_control.add_child(room_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	room_panel.add_child(vbox)

	var title := Label.new()
	title.text = "LOBBY"
	title.label_settings = _make_label_settings(24, COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	room_code_label = Label.new()
	room_code_label.text = ""
	room_code_label.label_settings = _make_label_settings(32, COLOR_GOLD)
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code_label.visible = false
	vbox.add_child(room_code_label)

	room_status_label = Label.new()
	room_status_label.text = ""
	room_status_label.label_settings = _make_label_settings(14, COLOR_TEXT, false)
	room_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	room_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(room_status_label)

	player_list_label = Label.new()
	player_list_label.text = "Players (0):"
	player_list_label.label_settings = _make_label_settings(14, COLOR_TEXT, false)
	player_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(player_list_label)

	start_button = Button.new()
	start_button.text = "START GAME"
	start_button.custom_minimum_size = Vector2(0, 42)
	start_button.visible = false
	start_button.pressed.connect(_on_start_game_pressed)
	vbox.add_child(start_button)

	leave_button = Button.new()
	leave_button.text = "← LEAVE LOBBY"
	leave_button.custom_minimum_size = Vector2(0, 38)
	leave_button.pressed.connect(_on_leave_lobby_pressed)
	vbox.add_child(leave_button)


func _on_leave_lobby_pressed() -> void:
	Network.disconnect_game()
	for p in players.values():
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	if is_instance_valid(spawner):
		spawner.queue_free()
	if is_instance_valid(player_container):
		player_container.queue_free()
	player = null
	mode = "menu"
	room_panel.visible = false
	start_button.visible = false
	menu_panel.visible = true
	_set_status(menu_status_label, "", COLOR_TEXT)
	Network.start_discovery()
	solo_menu_button.grab_focus()


func _setup_solo_prompt(root_control: Control) -> void:
	var panel := _make_panel(Vector2(560, 90))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.position = Vector2(-280, -110)
	panel.visible = false
	root_control.add_child(panel)
	solo_panel = panel

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	solo_prompt = Label.new()
	solo_prompt.text = "SOLO  --  Press X / Space to Enter the Game"
	solo_prompt.label_settings = _make_label_settings(24, COLOR_GOLD)
	solo_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(solo_prompt)

	solo_back_button = Button.new()
	solo_back_button.text = "← Back to Menu"
	solo_back_button.custom_minimum_size = Vector2(0, 34)
	solo_back_button.pressed.connect(_on_solo_back_pressed)
	vbox.add_child(solo_back_button)


func _on_solo_back_pressed() -> void:
	if is_instance_valid(player):
		player.queue_free()
	player = null
	mode = "menu"
	solo_panel.visible = false
	menu_panel.visible = true
	Network.start_discovery()
	solo_menu_button.grab_focus()


func _set_status(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.label_settings.font_color = color
