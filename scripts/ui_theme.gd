class_name UITheme
extends RefCounted
## Shared Godot Theme for every menu screen (Login, Lobby, etc.) so
## Buttons/LineEdits stop falling back to Godot's plain default grey
## widgets and actually match the game's "dramatic dark + spotlight
## gold" palette and Bebas Neue heading font established for the HUD.

const HEADING_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"

const COLOR_GOLD := Color(0xCA / 255.0, 0x8A / 255.0, 0x04 / 255.0)
const COLOR_GOLD_BRIGHT := Color(0xF2 / 255.0, 0xB2 / 255.0, 0x2C / 255.0)
const COLOR_GREEN := Color(0x22 / 255.0, 0xC5 / 255.0, 0x5E / 255.0)
const COLOR_RED := Color(0xEF / 255.0, 0x44 / 255.0, 0x44 / 255.0)
const COLOR_PANEL := Color(0x1B / 255.0, 0x1B / 255.0, 0x30 / 255.0, 0.94)
const COLOR_MUTED := Color(0x27 / 255.0, 0x27 / 255.0, 0x3B / 255.0, 1.0)
const COLOR_BORDER := Color(0x43 / 255.0, 0x38 / 255.0, 0xCA / 255.0, 0.55)
const COLOR_TEXT := Color(0xF8 / 255.0, 0xFA / 255.0, 0xFC / 255.0)
const COLOR_MUTED_TEXT := Color(0x94 / 255.0, 0xA3 / 255.0, 0xB8 / 255.0)


static func build() -> Theme:
	var theme := Theme.new()
	var heading_font: FontFile = load(HEADING_FONT)

	theme.set_font("font", "Button", heading_font)
	theme.set_font_size("font_size", "Button", 20)
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_GOLD)
	theme.set_color("font_disabled_color", "Button", COLOR_MUTED_TEXT)
	theme.set_stylebox("normal", "Button", _box(COLOR_MUTED, COLOR_BORDER, 2))
	theme.set_stylebox("hover", "Button", _box(COLOR_MUTED.lightened(0.1), COLOR_GOLD, 2))
	theme.set_stylebox("pressed", "Button", _box(COLOR_PANEL, COLOR_GOLD, 2))
	theme.set_stylebox("disabled", "Button", _box(COLOR_MUTED.darkened(0.35), Color(0, 0, 0, 0), 0))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), COLOR_GOLD_BRIGHT, 2))

	theme.set_font_size("font_size", "LineEdit", 17)
	theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_MUTED_TEXT)
	theme.set_color("caret_color", "LineEdit", COLOR_GOLD_BRIGHT)
	theme.set_stylebox("normal", "LineEdit", _box(COLOR_PANEL, COLOR_BORDER, 1))
	theme.set_stylebox("focus", "LineEdit", _box(COLOR_PANEL, COLOR_GOLD, 2))
	theme.set_stylebox("read_only", "LineEdit", _box(COLOR_MUTED.darkened(0.2), Color(0, 0, 0, 0), 0))

	theme.set_color("font_color", "Label", COLOR_TEXT)

	theme.set_stylebox("panel", "PanelContainer", _box(COLOR_PANEL, COLOR_BORDER, 1))

	return theme


static func field_label_settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = 14
	settings.font_color = COLOR_MUTED_TEXT
	return settings


static func _box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box
