extends Node3D
## "Red Light, Green Light" game mode.
## Loads the arena scene, generates collision for its ground/walls
## (a plain glTF import has none on its own), then runs the
## light-switching rules: move freely on green, freeze on red -- get
## caught moving and you're eliminated. The arena's own doll node
## doubles as our red/green "watcher"; the shared player/character
## setup still comes from WorldBuilder and Player.
##
## Multiplayer: if Network.is_networked, the host is authoritative
## for the light timer, doll, and elimination/win outcomes, and
## broadcasts them to every client via RPCs on this same node (each
## client's copy of this script receives the RPC and applies the
## matching local effect -- UI, doll rotation, sound -- to stay in
## sync). With no multiplayer peer active, everything runs exactly
## as it did in single-player.

const ARENA_SCENE := "res://assets/arena/squid_game_arena.glb"
const DOLL_BODY_NAME := "Doll_31"
const DOLL_HEAD_NAME := "DollHead_36"

# The whole arena (ground, walls, house, doll, everything) is scaled
# up so it reads as a giant, oversized set against a normal-sized
# player character, then wrapped in a 180-degree turn so its "start"
# wall ends up on the +Z side and its "doll/finish" end ends up on
# the -Z side, matching this project's existing forward-is--Z
# convention (see player.gd) without having to touch any movement code.
const ARENA_SCALE := 2.2
const SPAWN_Z := 26.0 * ARENA_SCALE
const FINISH_Z := -20.5 * ARENA_SCALE

const GREEN_MIN := 2.0
const GREEN_MAX := 4.5
const RED_MIN := 2.0
const RED_MAX := 4.0
const RED_GRACE := 0.35
const TIME_LIMIT := 90.0

const ANIM_DEATH := "Death"
const ANIM_VICTORY := "Victory"

const SFX_GREEN := "res://assets/audio/green_start.wav"
const SFX_RED := "res://assets/audio/red_buzzer.wav"
const SFX_ELIMINATED := "res://assets/audio/eliminated.wav"
const SFX_VICTORY := "res://assets/audio/victory.wav"
const SFX_DOLL_TURN := "res://assets/audio/doll_turn.wav"
const MUSIC_THEME := "res://assets/audio/theme_loop.wav"

const HEADING_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"

# Palette from the ui-ux-pro-max "dramatic dark + spotlight gold" system.
const COLOR_GOLD := Color(0xCA / 255.0, 0x8A / 255.0, 0x04 / 255.0)
const COLOR_GREEN := Color(0x22 / 255.0, 0xC5 / 255.0, 0x5E / 255.0)
const COLOR_RED := Color(0xEF / 255.0, 0x44 / 255.0, 0x44 / 255.0)
const COLOR_PANEL := Color(0x1B / 255.0, 0x1B / 255.0, 0x30 / 255.0, 0.55)
const COLOR_TEXT := Color(0xF8 / 255.0, 0xFA / 255.0, 0xFC / 255.0)

var arena_wrapper: Node3D
var player_container: Node3D
var spawner: MultiplayerSpawner
var players := {} # peer_id (int) -> CharacterBody3D

var player: CharacterBody3D # the LOCAL player, for convenience/back-compat
var doll: Node3D
var doll_head: Node3D
var doll_light: OmniLight3D

var sfx_green: AudioStreamPlayer
var sfx_red: AudioStreamPlayer
var sfx_eliminated: AudioStreamPlayer
var sfx_victory: AudioStreamPlayer
var sfx_doll_turn: AudioStreamPlayer
var music_player: AudioStreamPlayer

var flash_overlay: ColorRect
var heading_font: FontFile

var is_red_light := false
var state_time_left := 0.0
var red_light_elapsed := 0.0
var time_left := TIME_LIMIT
var my_result_shown := false
var _started_offline := false

var light_label: Label
var timer_label: Label
var message_label: Label
var restart_hint_label: Label

var pause_menu: Control
var pause_menu_open := false
var pause_resume_button: Button


func _ready() -> void:
	WorldBuilder.build_sky_environment(self)
	WorldBuilder.build_sun(self)
	_setup_imported_arena()
	_setup_doll()
	_setup_players()
	_setup_audio()
	_setup_ui()
	_setup_pause_menu()
	# Captured once, at start -- so a client that later loses connection
	# doesn't suddenly start thinking it's "offline" and take over the
	# host's rules with a now-broken multiplayer peer.
	_started_offline = not Network.is_networked
	if _is_host_or_offline():
		_start_green_light()


## Not gated by set_process(false) the way _process() can be (it's
## turned off once time runs out), so the pause menu always opens.
func _input(event: InputEvent) -> void:
	var toggled := false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggled = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		toggled = true
	if toggled:
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()


func _toggle_pause_menu() -> void:
	pause_menu_open = not pause_menu_open
	pause_menu.visible = pause_menu_open
	if pause_menu_open:
		pause_resume_button.grab_focus()
	if player and not my_result_shown:
		if pause_menu_open:
			player.freeze()
		else:
			player.unfreeze()


func _setup_pause_menu() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	pause_menu = Control.new()
	pause_menu.theme = UITheme.build()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	canvas.add_child(pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(dim)

	var panel := _make_panel(Vector2(340, 420))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-170, -210)
	pause_menu.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.label_settings = _make_label_settings(30, COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	pause_resume_button = Button.new()
	pause_resume_button.text = "RESUME"
	pause_resume_button.custom_minimum_size = Vector2(0, 44)
	pause_resume_button.pressed.connect(_toggle_pause_menu)
	vbox.add_child(pause_resume_button)

	var end_button := Button.new()
	end_button.text = "END GAME"
	end_button.custom_minimum_size = Vector2(0, 44)
	end_button.pressed.connect(_on_end_game_pressed)
	vbox.add_child(end_button)

	var end_hint := Label.new()
	end_hint.text = "Leaves this match and returns to the Lobby."
	end_hint.label_settings = _make_label_settings(13, COLOR_TEXT, false)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(end_hint)

	var minimize_button := Button.new()
	minimize_button.text = "MINIMIZE"
	minimize_button.custom_minimum_size = Vector2(0, 44)
	minimize_button.pressed.connect(_on_minimize_pressed)
	vbox.add_child(minimize_button)

	var quit_button := Button.new()
	quit_button.text = "QUIT GAME"
	quit_button.custom_minimum_size = Vector2(0, 44)
	quit_button.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_button)

	var logout_button := Button.new()
	logout_button.text = "LOG OUT"
	logout_button.custom_minimum_size = Vector2(0, 40)
	logout_button.pressed.connect(_on_logout_pressed)
	vbox.add_child(logout_button)

	var toggle_hint := Label.new()
	toggle_hint.text = "Esc / Options to open or close"
	toggle_hint.label_settings = _make_label_settings(12, COLOR_TEXT, false)
	toggle_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(toggle_hint)


func _on_end_game_pressed() -> void:
	if Network.is_networked:
		Network.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _on_minimize_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_logout_pressed() -> void:
	if Network.is_networked:
		Network.disconnect_game()
	Auth.sign_out()
	get_tree().change_scene_to_file("res://scenes/Login.tscn")


## True when this machine should run the game's rules: always true
## offline (single-player), true only for the host when networked.
func _is_host_or_offline() -> bool:
	return _started_offline or Network.is_host


func _process(delta: float) -> void:
	if my_result_shown:
		if Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_key_pressed(KEY_SPACE):
			if not Network.is_networked:
				get_tree().reload_current_scene()
		return

	if not _is_host_or_offline():
		return # clients just react to the host's RPCs

	time_left = max(time_left - delta, 0.0)
	rpc(&"rpc_update_timer", ceili(time_left))
	if time_left <= 0.0:
		for peer_id in players.keys():
			var p: CharacterBody3D = players[peer_id]
			if is_instance_valid(p) and not p.frozen:
				rpc(&"rpc_player_result", peer_id, false, "TIME'S UP")
		set_process(false)
		return

	state_time_left -= delta
	if is_red_light:
		red_light_elapsed += delta
		if red_light_elapsed > RED_GRACE:
			for peer_id in players.keys():
				var p: CharacterBody3D = players[peer_id]
				if is_instance_valid(p) and not p.frozen and p.is_input_active:
					rpc(&"rpc_player_result", peer_id, false, "ELIMINATED")

	if state_time_left <= 0.0:
		if is_red_light:
			_start_green_light()
		else:
			_start_red_light()

	for peer_id in players.keys():
		var p: CharacterBody3D = players[peer_id]
		if is_instance_valid(p) and not p.frozen and p.global_position.z <= FINISH_Z:
			rpc(&"rpc_player_result", peer_id, true, "YOU WIN")


func _start_green_light() -> void:
	is_red_light = false
	red_light_elapsed = 0.0
	state_time_left = randf_range(GREEN_MIN, GREEN_MAX)
	rpc(&"rpc_set_light", false)


func _start_red_light() -> void:
	is_red_light = true
	red_light_elapsed = 0.0
	state_time_left = randf_range(RED_MIN, RED_MAX)
	rpc(&"rpc_set_light", true)


@rpc("authority", "call_local", "reliable")
func rpc_set_light(red: bool) -> void:
	if red:
		light_label.text = "RED LIGHT"
		light_label.label_settings.font_color = COLOR_RED
		doll_light.light_color = Color(1.0, 0.25, 0.25)
		sfx_red.play()
	else:
		light_label.text = "GREEN LIGHT"
		light_label.label_settings.font_color = COLOR_GREEN
		doll_light.light_color = Color(0.3, 1.0, 0.3)
		sfx_green.play()
	_face_doll(red)


@rpc("authority", "call_local", "unreliable_ordered")
func rpc_update_timer(seconds_left: int) -> void:
	timer_label.text = "Time: %d" % seconds_left


@rpc("authority", "call_local", "reliable")
func rpc_player_result(peer_id: int, won: bool, message: String) -> void:
	var p: CharacterBody3D = players.get(peer_id)
	if not is_instance_valid(p) or p.frozen:
		return
	p.play_animation(ANIM_VICTORY if won else ANIM_DEATH)
	p.freeze()
	if won:
		sfx_victory.play()
	else:
		sfx_eliminated.play()
		_spawn_blood_pool(p.global_position)
		_spawn_blood_spray(p.global_position)

	var is_me := peer_id == multiplayer.get_unique_id() or not Network.is_networked
	if is_me:
		_show_local_result(won, message)


func _show_local_result(won: bool, message: String) -> void:
	if my_result_shown:
		return
	my_result_shown = true
	message_label.text = message
	message_label.label_settings.font_color = COLOR_GREEN if won else COLOR_RED
	message_label.visible = true
	restart_hint_label.visible = true
	if not won:
		if player:
			player.shake_camera(0.25, 0.5)
		_flash_screen(Color(0.9, 0.1, 0.1, 0.55))
	var music_tween := create_tween()
	music_tween.tween_property(music_player, "volume_db", -40.0, 1.0)


func _face_doll(watching: bool) -> void:
	if doll_head == null:
		return
	sfx_doll_turn.play()
	var tween := create_tween()
	# watching (red light) = head turns to face the players (danger);
	# not watching (green light) = head turns back toward the tree/away.
	var target_y := 0.0 if watching else 180.0
	tween.tween_property(doll_head, "rotation_degrees:y", target_y, 0.4)


func _flash_screen(color: Color) -> void:
	flash_overlay.color = color
	var tween := create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, 0.5)


func _spawn_blood_pool(at_position: Vector3) -> void:
	var pool := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 24
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.02, 0.03, 0.85)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	pool.mesh = mesh
	pool.position = Vector3(at_position.x, 0.02, at_position.z)
	add_child(pool)

	# Grow the pool in from nothing for a bit of impact.
	pool.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(pool, "scale", Vector3(1.4, 1.0, 1.1), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A short burst of falling blood drops from roughly chest height,
## like a gunshot hit -- on top of the pool that forms on the ground.
func _spawn_blood_spray(at_position: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.position = at_position + Vector3(0, 1.4, 0)
	particles.one_shot = true
	particles.amount = 40
	particles.lifetime = 1.2
	particles.explosiveness = 0.9
	particles.local_coords = false

	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.035
	drop_mesh.height = 0.07
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.5, 0.02, 0.03)
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh.material = drop_material
	particles.draw_pass_1 = drop_mesh

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 60.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 5.0
	process_material.gravity = Vector3(0, -9.8, 0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.4
	particles.process_material = process_material

	add_child(particles)
	particles.emitting = true

	var cleanup_timer := get_tree().create_timer(particles.lifetime + 0.5)
	cleanup_timer.timeout.connect(particles.queue_free)


## Loads the downloaded arena scene (ground, walls, houses, dead
## tree, finish line, doll -- all in one file) and generates physics
## collision for its playable boundary, since a plain glTF import
## has none on its own.
func _setup_imported_arena() -> void:
	var arena_scene: PackedScene = load(ARENA_SCENE)

	arena_wrapper = Node3D.new()
	arena_wrapper.name = "Arena"
	arena_wrapper.rotation_degrees.y = 180.0
	arena_wrapper.scale = Vector3.ONE * ARENA_SCALE
	add_child(arena_wrapper)

	var arena := arena_scene.instantiate()
	arena_wrapper.add_child(arena)

	for mesh_name in ["Ground_0", "LeftWall_1", "RightWall_2", "StartWaill_3", "EndWall_4"]:
		WorldBuilder.add_collision_for(arena, mesh_name)

	# Dramatic overhead spotlights down the run.
	for spot_z in [SPAWN_Z - 6.0 * ARENA_SCALE, 0.0, FINISH_Z + 6.0 * ARENA_SCALE]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, 13.0 * ARENA_SCALE, spot_z)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.spot_range = 18.0 * ARENA_SCALE
		spot.spot_angle = 45.0
		spot.light_energy = 1.4
		spot.light_color = Color(1.0, 0.97, 0.9)
		add_child(spot)


## The arena scene already includes its own doll -- find its body and
## its (separate) head node and reuse them directly as the red/green
## "watcher" instead of spawning a second doll. Only the head turns;
## the body stays put, matching the real game's head-turn beat.
func _setup_doll() -> void:
	doll = WorldBuilder.find_child_by_name(arena_wrapper, DOLL_BODY_NAME)
	doll_head = WorldBuilder.find_child_by_name(arena_wrapper, DOLL_HEAD_NAME)
	if doll == null:
		push_warning("Doll node '%s' not found in arena scene" % DOLL_BODY_NAME)
		return
	if doll_head == null:
		push_warning("Doll head node '%s' not found in arena scene" % DOLL_HEAD_NAME)

	doll_light = OmniLight3D.new()
	doll_light.position = Vector3(0, 1.0, 0.3)
	doll_light.light_energy = 2.5
	doll_light.omni_range = 5.0
	doll.add_child(doll_light)

	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 5.0, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_range = 10.0
	spot.spot_angle = 30.0
	spot.light_energy = 3.0
	spot.light_color = Color(1.0, 0.88, 0.6) # warm golden daylight
	doll.add_child(spot)


## Single-player: spawns one local character directly, exactly as
## before. Networked: sets up a MultiplayerSpawner so every peer ends
## up with an identical, correctly-authorized character per player.
func _setup_players() -> void:
	if not Network.is_networked:
		player = WorldBuilder.spawn_player(self, Vector3(0, 2, SPAWN_Z))
		player.username = Auth.username if not Auth.username.is_empty() else "Player"
		WorldBuilder.apply_customization(player)
		players[1] = player
		return

	player_container = Node3D.new()
	player_container.name = "Players"
	add_child(player_container)

	spawner = MultiplayerSpawner.new()
	# See the matching comment in lobby.gd: an auto-generated name can
	# number differently across peers and break spawn replication, so
	# this needs to be identical on every machine.
	spawner.name = "PlayerSpawner"
	add_child(spawner)
	spawner.spawn_path = player_container.get_path()
	spawner.spawn_function = _create_networked_player

	Network.player_connected.connect(_on_player_connected)
	Network.player_disconnected.connect(_on_player_disconnected)

	if Network.is_host:
		_request_spawn(1)
		for id in multiplayer.get_peers():
			_request_spawn(id)


func _on_player_connected(peer_id: int) -> void:
	if Network.is_host:
		_request_spawn(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	# MultiplayerSpawner already despawns nodes tied to a disconnecting
	# peer's authority on its own; just drop our reference, and only
	# free it ourselves if it's somehow still around.
	if players.has(peer_id):
		var p = players[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(peer_id)


func _request_spawn(peer_id: int) -> void:
	if players.has(peer_id):
		return
	spawner.spawn(peer_id)


## Runs on every peer: the host calls spawner.spawn(peer_id), Godot
## replicates that call, and this same function runs locally on each
## machine so everyone builds an identical instance with matching
## multiplayer authority.
func _create_networked_player(peer_id: int) -> CharacterBody3D:
	var player_scene: PackedScene = load(WorldBuilder.PLAYER_SCENE)
	var new_player: CharacterBody3D = player_scene.instantiate()
	new_player.name = "Player_%d" % peer_id
	new_player.position = Vector3(randf_range(-3.0, 3.0), 2, SPAWN_Z)
	new_player.set_multiplayer_authority(peer_id)
	players[peer_id] = new_player
	if peer_id == multiplayer.get_unique_id():
		player = new_player
		new_player.username = Auth.username if not Auth.username.is_empty() else "Player"
		WorldBuilder.apply_customization(new_player)
	return new_player


func _setup_audio() -> void:
	sfx_green = AudioStreamPlayer.new()
	sfx_green.stream = load(SFX_GREEN)
	add_child(sfx_green)

	sfx_red = AudioStreamPlayer.new()
	sfx_red.stream = load(SFX_RED)
	add_child(sfx_red)

	sfx_eliminated = AudioStreamPlayer.new()
	sfx_eliminated.stream = load(SFX_ELIMINATED)
	add_child(sfx_eliminated)

	sfx_victory = AudioStreamPlayer.new()
	sfx_victory.stream = load(SFX_VICTORY)
	add_child(sfx_victory)

	sfx_doll_turn = AudioStreamPlayer.new()
	sfx_doll_turn.stream = load(SFX_DOLL_TURN)
	sfx_doll_turn.volume_db = -6.0
	add_child(sfx_doll_turn)

	# Original tension theme (not a reproduction of any existing
	# copyrighted track) -- a music-box loop under the game.
	music_player = AudioStreamPlayer.new()
	var music_stream: AudioStreamWAV = load(MUSIC_THEME)
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music_player.stream = music_stream
	music_player.volume_db = -3.0
	add_child(music_player)
	music_player.play()


func _make_label_settings(size: int, color: Color, use_heading_font: bool = true) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	if use_heading_font and heading_font:
		settings.font = heading_font
	settings.outline_size = 8
	settings.outline_color = Color(0.05, 0.05, 0.08, 0.9)
	settings.shadow_size = 4
	settings.shadow_color = Color(0, 0, 0, 0.5)
	settings.shadow_offset = Vector2(2, 3)
	return settings


func _make_panel(size: Vector2) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = size
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _setup_ui() -> void:
	heading_font = load(HEADING_FONT)

	var canvas := CanvasLayer.new()
	add_child(canvas)

	var light_panel := _make_panel(Vector2(280, 64))
	light_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	light_panel.position = Vector2(-140, 16)
	light_panel.anchor_left = 0.5
	light_panel.anchor_right = 0.5
	canvas.add_child(light_panel)

	light_label = Label.new()
	light_label.text = "GREEN LIGHT"
	light_label.label_settings = _make_label_settings(38, COLOR_GREEN)
	light_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	light_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	light_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	light_panel.add_child(light_label)

	var timer_panel := _make_panel(Vector2(150, 46))
	timer_panel.position = Vector2(20, 20)
	canvas.add_child(timer_panel)

	timer_label = Label.new()
	timer_label.text = "Time: %d" % int(TIME_LIMIT)
	timer_label.label_settings = _make_label_settings(22, COLOR_GOLD, false)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	timer_panel.add_child(timer_label)

	message_label = Label.new()
	message_label.text = ""
	message_label.visible = false
	message_label.label_settings = _make_label_settings(72, COLOR_TEXT)
	message_label.set_anchors_preset(Control.PRESET_CENTER)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.position = Vector2(-320, -80)
	message_label.size = Vector2(640, 110)
	canvas.add_child(message_label)

	restart_hint_label = Label.new()
	restart_hint_label.text = "Press X / Space to restart"
	restart_hint_label.visible = false
	restart_hint_label.label_settings = _make_label_settings(22, COLOR_TEXT, false)
	restart_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	restart_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_hint_label.position = Vector2(-320, 30)
	restart_hint_label.size = Vector2(640, 50)
	canvas.add_child(restart_hint_label)

	flash_overlay = ColorRect.new()
	flash_overlay.color = Color(1, 0, 0, 0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(flash_overlay)
