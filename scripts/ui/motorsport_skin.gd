extends RefCounted

const PAPER := preload("res://assets/ui/imagine/motorsport_panel_paper.png")
const DARK := preload("res://assets/ui/imagine/motorsport_panel_dark.png")
const INK := Color("12232a")
const CREAM := Color("fff2ce")
const AMBER := Color("f4bf52")
const TEAL := Color("71c9bc")
const MUTED := Color("9caaa9")
const BORDER := 12.0


static func panel(primary: bool, state: String = "normal") -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PAPER if primary else DARK
	style.set_texture_margin_all(BORDER)
	style.modulate_color = Color(1.0, 0.88, 0.60) if primary else Color(0.86, 0.98, 1.0)
	if state == "hover":
		style.modulate_color = Color(1.12, 1.02, 0.82) if primary else Color(1.45, 1.65, 1.7)
	elif state in ["pressed", "hover_pressed"]:
		style.modulate_color = Color(0.82, 0.70, 0.48) if primary else Color(0.64, 0.78, 0.83)
	elif state == "disabled":
		style.modulate_color = Color(0.53, 0.57, 0.60)
	style.content_margin_left = 44.0 if primary else 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0 if state in ["pressed", "hover_pressed"] else 8.0
	style.content_margin_bottom = 6.0 if state in ["pressed", "hover_pressed"] else 8.0
	return style


static func focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = TEAL
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_expand_margin_all(3)
	return style


static func apply_button(button: Button, primary: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, panel(primary, state))
	button.add_theme_stylebox_override("focus", focus_style())
	button.add_theme_color_override("font_color", INK if primary else CREAM)
	button.add_theme_color_override("font_hover_color", INK if primary else TEAL)
	button.add_theme_color_override("font_focus_color", INK if primary else CREAM)
	button.add_theme_color_override("font_pressed_color", INK if primary else CREAM)
	button.add_theme_color_override("font_hover_pressed_color", INK if primary else CREAM)
	button.add_theme_color_override("font_disabled_color", INK if primary else MUTED)
	if button.has_method("set_art_role"):
		button.call("set_art_role", primary)
