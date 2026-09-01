extends Node3D
## Login / sign-up screen -- a pure 2D card UI (no 3D world), modernized:
## glassmorphic card, richer layered gradient backdrop, refined type scale,
## soft glow rings, and subtle hover micro-interactions on top of the
## original sage/ink/amber palette. Same node names / signals / logic as
## before -- only visuals were pushed further. Talks to the autoloaded
## Auth singleton (local by default; swap the autoload target to go back
## to a real backend without touching this file).

const NEXT_SCENE := "res://scenes/Lobby.tscn"

const FONT_HEADING := "res://assets/fonts/Fraunces-Medium.ttf"
const FONT_BODY := "res://assets/fonts/SpaceGrotesk-Regular.ttf"
const FONT_BODY_BOLD := "res://assets/fonts/SpaceGrotesk-SemiBold.ttf"

const COLOR_INK := Color(0x0B / 255.0, 0x22 / 255.0, 0x1F / 255.0)
const COLOR_INK_2 := Color(0x0F / 255.0, 0x2C / 255.0, 0x28 / 255.0)
const COLOR_SAGE := Color(0xEA / 255.0, 0xF1 / 255.0, 0xEC / 255.0)
const COLOR_SAGE_2 := Color(0xF5 / 255.0, 0xFA / 255.0, 0xF7 / 255.0)
const COLOR_TEXT_DARK := Color(0x12 / 255.0, 0x20 / 255.0, 0x1C / 255.0)
const COLOR_TEXT_MUTED := Color(0x5C / 255.0, 0x6D / 255.0, 0x66 / 255.0)
const COLOR_AMBER := Color(0xF0 / 255.0, 0xB0 / 255.0, 0x52 / 255.0)
const COLOR_AMBER_DEEP := Color(0xCE / 255.0, 0x8A / 255.0, 0x32 / 255.0)
const COLOR_TEAL_GLOW := Color(0x2E / 255.0, 0x8B / 255.0, 0x77 / 255.0)
const COLOR_LINE := Color(0x14 / 255.0, 0x24 / 255.0, 0x20 / 255.0, 0.12)
const COLOR_ERROR := Color(0xC4 / 255.0, 0x3B / 255.0, 0x3B / 255.0)

var font_heading: FontFile
var font_body: FontFile
var font_body_bold: FontFile

var card: Control
var login_face: Control
var signup_face: Control
var is_signup_mode := false

var login_email: LineEdit
var login_password: LineEdit
var login_button: Button
var login_status: Label

var signup_username: LineEdit
var signup_email: LineEdit
var signup_password: LineEdit
var signup_button: Button
var signup_status: Label

var canvas_root: CanvasLayer


func _ready() -> void:
	font_heading = load(FONT_HEADING)
	font_body = load(FONT_BODY)
	font_body_bold = load(FONT_BODY_BOLD)

	_setup_backdrop()
	_setup_card()
	_setup_quit_button()
	_play_entrance()

	# Gamepad D-pad/left-stick + Cross (Godot's default ui_up/down/
	# left/right/accept, already bound to joypad out of the box) needs
	# an initial focus target to start navigating from.
	login_email.grab_focus()

	Auth.sign_up_succeeded.connect(_on_sign_up_succeeded)
	Auth.sign_up_failed.connect(_on_sign_up_failed)
	Auth.sign_in_succeeded.connect(_on_sign_in_succeeded)
	Auth.sign_in_failed.connect(_on_sign_in_failed)


# ---------------------------------------------------------------- backdrop

func _setup_backdrop() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	canvas_root = canvas

	# Deep vertical gradient base instead of a flat fill -- reads far
	# less "solid color rect" and gives the glow blobs something to sit on.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_shader := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 color_top : source_color = vec4(0.043, 0.133, 0.122, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.02, 0.07, 0.065, 1.0);
void fragment() {
	COLOR = mix(color_top, color_bottom, UV.y);
}
"""
	bg_shader.shader = shader
	bg_shader.set_shader_parameter("color_top", Color(0x11 / 255.0, 0x2E / 255.0, 0x2A / 255.0))
	bg_shader.set_shader_parameter("color_bottom", Color(0x07 / 255.0, 0x17 / 255.0, 0x15 / 255.0))
	bg.material = bg_shader
	bg.color = COLOR_INK
	canvas.add_child(bg)

	# Fine noise/grain-free glow layer: several soft radial blobs, layered
	# and drifting slowly for a subtle "alive" feel.
	var blob_layer := Control.new()
	blob_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	blob_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(blob_layer)

	var blob1 := _make_blob(COLOR_AMBER, 760.0, 0.42)
	blob1.position = Vector2(-260, -260)
	blob_layer.add_child(blob1)
	_drift(blob1, Vector2(55, 40), 10.0)

	var blob2 := _make_blob(COLOR_TEAL_GLOW, 700.0, 0.5)
	blob2.anchor_left = 1.0
	blob2.anchor_top = 1.0
	blob2.position = Vector2(-520, -580)
	blob_layer.add_child(blob2)
	_drift(blob2, Vector2(-45, -32), 12.5)

	var blob3 := _make_blob(COLOR_AMBER_DEEP, 460.0, 0.32)
	blob3.anchor_left = 1.0
	blob3.position = Vector2(-300, 300)
	blob_layer.add_child(blob3)
	_drift(blob3, Vector2(-28, 34), 14.0)

	var blob4 := _make_blob(Color(0x3D / 255.0, 0x7A / 255.0, 0x6B / 255.0), 380.0, 0.3)
	blob4.anchor_top = 1.0
	blob4.position = Vector2(60, -420)
	blob_layer.add_child(blob4)
	_drift(blob4, Vector2(30, -22), 8.5)

	# Thin vignette to pull focus back toward center/card.
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vshader := ShaderMaterial.new()
	var vshader_res := Shader.new()
	vshader_res.code = """
shader_type canvas_item;
void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c * vec2(1.0, 1.2));
	float a = smoothstep(0.35, 0.85, d) * 0.45;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	vshader.shader = vshader_res
	vignette.material = vshader
	canvas.add_child(vignette)


func _setup_quit_button() -> void:
	var button := Button.new()
	button.text = "✕  Quit"
	button.flat = true
	button.custom_minimum_size = Vector2(96, 36)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = Vector2(-116, 24)
	button.add_theme_font_override("font", font_body_bold)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(COLOR_SAGE.r, COLOR_SAGE.g, COLOR_SAGE.b, 0.65))
	button.add_theme_color_override("font_hover_color", COLOR_SAGE)
	button.pressed.connect(func(): get_tree().quit())
	canvas_root.add_child(button)


func _make_blob(color: Color, size: float, alpha: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, alpha))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(size)
	texture.height = int(size)

	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _drift(node: Control, offset: Vector2, duration: float) -> void:
	var start_pos := node.position
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(node, "position", start_pos + offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", start_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# -------------------------------------------------------------------- card

func _setup_card() -> void:
	# Left half of the screen: a big brand moment, so a 1920x1080
	# window doesn't read as "small card floating in empty space."
	var brand_block := Control.new()
	brand_block.set_anchors_preset(Control.PRESET_FULL_RECT)
	brand_block.anchor_right = 0.52
	brand_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_root.add_child(brand_block)

	var brand_vbox := VBoxContainer.new()
	brand_vbox.set_anchors_preset(Control.PRESET_CENTER)
	brand_vbox.position = Vector2(-270, -130)
	brand_vbox.custom_minimum_size = Vector2(540, 260)
	brand_vbox.add_theme_constant_override("separation", 20)
	brand_block.add_child(brand_vbox)

	# Small pill badge above the title for a more "product" feel.
	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.16)
	badge_style.border_color = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.45)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(999)
	badge_style.content_margin_left = 14
	badge_style.content_margin_right = 14
	badge_style.content_margin_top = 6
	badge_style.content_margin_bottom = 6
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var badge_label := Label.new()
	badge_label.text = "● LIVE LOBBIES OPEN"
	badge_label.label_settings = _label_settings(font_body_bold, 12, COLOR_AMBER)
	badge.add_child(badge_label)
	brand_vbox.add_child(badge)

	var brand_title := Label.new()
	brand_title.text = "ORPHIJ"
	brand_title.label_settings = _label_settings(font_heading, 92, COLOR_SAGE)
	brand_vbox.add_child(brand_title)

	var brand_tag := Label.new()
	brand_tag.text = "Red Light, Green Light. Gather your friends and see who's still standing."
	brand_tag.label_settings = _label_settings(font_body, 19, Color(COLOR_SAGE.r, COLOR_SAGE.g, COLOR_SAGE.b, 0.72))
	brand_tag.custom_minimum_size = Vector2(460, 0)
	brand_tag.autowrap_mode = TextServer.AUTOWRAP_WORD
	brand_vbox.add_child(brand_tag)

	# Right side: the auth card itself.
	var scene_root := Control.new()
	scene_root.anchor_left = 0.68
	scene_root.anchor_right = 0.68
	scene_root.anchor_top = 0.5
	scene_root.anchor_bottom = 0.5
	scene_root.position = Vector2(-240, -300)
	scene_root.custom_minimum_size = Vector2(480, 600)
	scene_root.size = Vector2(480, 600)
	scene_root.pivot_offset = Vector2(240, 300)
	canvas_root.add_child(scene_root)
	card = scene_root

	# Soft glow ring behind the card for depth/separation from the backdrop.
	var glow_ring := Panel.new()
	glow_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_ring.position = Vector2(-14, -14)
	glow_ring.size = Vector2(508, 628)
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.set_corner_radius_all(34)
	glow_style.shadow_size = 60
	glow_style.shadow_color = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.18)
	glow_ring.add_theme_stylebox_override("panel", glow_style)
	glow_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(glow_ring)
	card.move_child(glow_ring, 0)

	login_face = _build_face(true)
	login_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(login_face)

	signup_face = _build_face(false)
	signup_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	signup_face.visible = false
	card.add_child(signup_face)


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Slightly translucent "glass" card rather than a flat opaque fill --
	# paired with a faint border it reads as frosted glass over the glow.
	style.bg_color = Color(COLOR_SAGE.r, COLOR_SAGE.g, COLOR_SAGE.b, 0.97)
	style.border_color = Color(1, 1, 1, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(26)
	style.shadow_size = 44
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_offset = Vector2(0, 20)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 36
	style.content_margin_bottom = 32
	return style


func _build_face(is_login: bool) -> Control:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _card_style())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var eyebrow := HBoxContainer.new()
	vbox.add_child(eyebrow)

	# Small amber dot mark next to the wordmark for a more "logo" feel.
	var mark := ColorRect.new()
	mark.color = COLOR_AMBER_DEEP
	mark.custom_minimum_size = Vector2(8, 8)
	mark.size = Vector2(8, 8)
	var mark_center := CenterContainer.new()
	mark_center.custom_minimum_size = Vector2(16, 20)
	mark_center.add_child(mark)
	eyebrow.add_child(mark_center)

	var brand := Label.new()
	brand.text = "Orphij"
	brand.label_settings = _label_settings(font_body_bold, 14, COLOR_TEXT_DARK)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow.add_child(brand)

	var step_pill := PanelContainer.new()
	var step_style := StyleBoxFlat.new()
	step_style.bg_color = Color(COLOR_TEXT_DARK.r, COLOR_TEXT_DARK.g, COLOR_TEXT_DARK.b, 0.06)
	step_style.set_corner_radius_all(999)
	step_style.content_margin_left = 10
	step_style.content_margin_right = 10
	step_style.content_margin_top = 3
	step_style.content_margin_bottom = 3
	step_pill.add_theme_stylebox_override("panel", step_style)
	var step := Label.new()
	step.text = "SIGN IN" if is_login else "SIGN UP"
	step.label_settings = _label_settings(font_body_bold, 11, COLOR_TEXT_MUTED)
	step_pill.add_child(step)
	eyebrow.add_child(step_pill)

	var mark_spacer := Control.new()
	mark_spacer.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(mark_spacer)

	var title := Label.new()
	title.text = "Welcome back" if is_login else "Join the arena"
	title.label_settings = _label_settings(font_heading, 32, COLOR_TEXT_DARK)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pick up right where you left off." if is_login else "Takes less than a minute."
	subtitle.label_settings = _label_settings(font_body, 14, COLOR_TEXT_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(subtitle)

	var field_spacer := Control.new()
	field_spacer.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(field_spacer)

	if is_login:
		var email_field := _make_floating_field("Email")
		vbox.add_child(email_field.container)
		login_email = email_field.line_edit

		var pass_field := _make_floating_field("Password", true)
		vbox.add_child(pass_field.container)
		login_password = pass_field.line_edit

		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		vbox.add_child(gap)

		login_button = _make_primary_button("SIGN IN")
		login_button.pressed.connect(_on_login_pressed)
		vbox.add_child(login_button)

		login_status = Label.new()
		login_status.label_settings = _label_settings(font_body, 13, COLOR_TEXT_MUTED)
		login_status.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(login_status)

		var switch1 := _make_link_button("New here? Create an account")
		switch1.pressed.connect(_switch_mode.bind(true))
		vbox.add_child(switch1)
	else:
		var user_field := _make_floating_field("Username")
		vbox.add_child(user_field.container)
		signup_username = user_field.line_edit

		var email_field2 := _make_floating_field("Email")
		vbox.add_child(email_field2.container)
		signup_email = email_field2.line_edit

		var pass_field2 := _make_floating_field("Password", true)
		vbox.add_child(pass_field2.container)
		signup_password = pass_field2.line_edit

		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(0, 10)
		vbox.add_child(gap2)

		signup_button = _make_primary_button("CREATE ACCOUNT")
		signup_button.pressed.connect(_on_signup_pressed)
		vbox.add_child(signup_button)

		signup_status = Label.new()
		signup_status.label_settings = _label_settings(font_body, 13, COLOR_TEXT_MUTED)
		signup_status.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(signup_status)

		var switch2 := _make_link_button("Already have an account? Sign in")
		switch2.pressed.connect(_switch_mode.bind(false))
		vbox.add_child(switch2)

	return panel


func _label_settings(font: FontFile, size: int, color: Color) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = size
	settings.font_color = color
	return settings


func _make_primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 50)
	button.pivot_offset = Vector2(0, 25)

	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_INK
	normal.set_corner_radius_all(14)

	var hover := normal.duplicate()
	hover.bg_color = COLOR_INK_2
	hover.shadow_size = 18
	hover.shadow_color = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.25)

	var disabled := normal.duplicate()
	disabled.bg_color = COLOR_TEXT_MUTED

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_font_override("font", font_body_bold)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", COLOR_SAGE)
	button.add_theme_color_override("font_hover_color", COLOR_SAGE)
	button.add_theme_color_override("font_disabled_color", COLOR_SAGE_2)

	# Tiny lift-on-hover micro-interaction.
	button.mouse_entered.connect(func():
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2(1.015, 1.03), 0.12).set_trans(Tween.TRANS_SINE)
	)
	button.mouse_exited.connect(func():
		var t := button.create_tween()
		t.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE)
	)
	return button


func _make_link_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.add_theme_font_override("font", font_body_bold)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_AMBER_DEEP)
	button.add_theme_color_override("font_hover_color", COLOR_AMBER)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var top_gap := 16
	button.add_theme_constant_override("outline_size", 0)
	button.custom_minimum_size = Vector2(0, 30 + top_gap)
	return button


func _make_floating_field(label_text: String, secret: bool = false) -> Dictionary:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 56)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_SAGE_2
	normal_style.border_color = COLOR_LINE
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(14)
	normal_style.content_margin_left = 16
	normal_style.content_margin_right = 16

	var focus_style := normal_style.duplicate()
	focus_style.border_color = COLOR_AMBER_DEEP
	focus_style.set_border_width_all(2)
	focus_style.shadow_size = 10
	focus_style.shadow_color = Color(COLOR_AMBER_DEEP.r, COLOR_AMBER_DEEP.g, COLOR_AMBER_DEEP.b, 0.16)

	var line_edit := LineEdit.new()
	line_edit.secret = secret
	line_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
	line_edit.add_theme_font_override("font", font_body)
	line_edit.add_theme_font_size_override("font_size", 15)
	line_edit.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	line_edit.add_theme_color_override("caret_color", COLOR_AMBER_DEEP)
	container.add_child(line_edit)

	var label := Label.new()
	label.text = label_text
	label.label_settings = _label_settings(font_body, 15, COLOR_TEXT_MUTED)
	label.position = Vector2(17, 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(label)

	var floated := false

	var update_state := func() -> void:
		var should_float: bool = line_edit.has_focus() or not line_edit.text.is_empty()
		if should_float == floated:
			return
		floated = should_float
		var tween := container.create_tween()
		tween.set_parallel(true)
		var target_pos: Vector2 = Vector2(15, 7) if floated else Vector2(17, 17)
		var target_scale: Vector2 = Vector2(0.72, 0.72) if floated else Vector2.ONE
		tween.tween_property(label, "position", target_pos, 0.16).set_trans(Tween.TRANS_SINE)
		tween.tween_property(label, "scale", target_scale, 0.16).set_trans(Tween.TRANS_SINE)
		label.label_settings.font_color = COLOR_AMBER_DEEP if floated else COLOR_TEXT_MUTED

	line_edit.focus_entered.connect(func(): update_state.call())
	line_edit.focus_exited.connect(func(): update_state.call())
	line_edit.text_changed.connect(func(_t): update_state.call())

	return {"container": container, "line_edit": line_edit}


# ------------------------------------------------------------- entrance fx

func _play_entrance() -> void:
	card.scale = Vector2(0.94, 0.94)
	card.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------- switching

func _switch_mode(target_signup: bool) -> void:
	if is_signup_mode == target_signup:
		return
	is_signup_mode = target_signup

	var tween := create_tween()
	tween.tween_property(card, "scale:x", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_swap_faces)
	tween.tween_property(card, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _swap_faces() -> void:
	login_face.visible = not is_signup_mode
	signup_face.visible = is_signup_mode
	# So a gamepad (D-pad/stick + Cross to "click") has something to
	# start navigating from on whichever face just became visible.
	if is_signup_mode:
		signup_username.grab_focus()
	else:
		login_email.grab_focus()


# ------------------------------------------------------------------- auth

func _on_signup_pressed() -> void:
	if signup_email.text.is_empty() or signup_password.text.is_empty() or signup_username.text.is_empty():
		_set_status(signup_status, "Please fill in username, email, and password.", COLOR_ERROR)
		return
	_set_status(signup_status, "Creating account...", COLOR_TEXT_MUTED)
	signup_button.disabled = true
	Auth.sign_up(signup_email.text, signup_password.text, signup_username.text)


func _on_login_pressed() -> void:
	if login_email.text.is_empty() or login_password.text.is_empty():
		_set_status(login_status, "Please fill in email and password.", COLOR_ERROR)
		return
	_set_status(login_status, "Signing in...", COLOR_TEXT_MUTED)
	login_button.disabled = true
	Auth.sign_in(login_email.text, login_password.text)


func _on_sign_up_succeeded(_needs_email_confirmation: bool) -> void:
	signup_button.disabled = false
	_set_status(signup_status, "Account created! Please sign in.", Color(0x2E / 255.0, 0x7D / 255.0, 0x5A / 255.0))
	_switch_mode(false)


func _on_sign_up_failed(message: String) -> void:
	signup_button.disabled = false
	_set_status(signup_status, message, COLOR_ERROR)


func _on_sign_in_succeeded() -> void:
	_set_status(login_status, "Welcome!", Color(0x2E / 255.0, 0x7D / 255.0, 0x5A / 255.0))
	get_tree().change_scene_to_file(NEXT_SCENE)


func _on_sign_in_failed(message: String) -> void:
	login_button.disabled = false
	_set_status(login_status, message, COLOR_ERROR)


func _set_status(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.label_settings.font_color = color