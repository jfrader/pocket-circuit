extends Control

## A stop on the tabletop map: the stop kind's map icon set on a physical chip,
## with a soft contact shadow. Selection lifts it; hover brightens its rim.

const UI := preload("res://scripts/ui/run_ui.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SHADOW := Color(0.025, 0.035, 0.06, 0.62)
const CHIP_RADIUS := 18.0
const BOSS_RADIUS := 20.0
const EDGE_DEPTH := 3.0
const ICON_EXTENT := 28.0
const FACE := Color("26332e")
const EDGE := Color("111815")
## Each kind's rim, taken from its map icon so chip, icon and legend agree.
const RIMS := {
	"race": Color("8b95a5"), "rival": Color("d4574c"), "bench": Color("6fbf8f"), "parts_van": Color("f2a53c"),
	"lockup": Color("efc94c"), "errand": Color("6aa8d8"), "act_rival": Color("f2a53c"),
}
const LIFT := 3.0
var kind := "race"
var selected := false
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()
var done := false:
	set(value):
		done = value
		queue_redraw()
var reduced_motion := false
var lift := 0.0:
	set(value):
		lift = value
		queue_redraw()
var _lift_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func icon() -> Texture2D:
	return UI.TYPES[kind]["icon"] as Texture2D


func radius() -> float:
	return BOSS_RADIUS if kind == "act_rival" else CHIP_RADIUS


func set_selected(value: bool) -> void:
	selected = value
	if _lift_tween != null:
		_lift_tween.kill()
	if reduced_motion:
		lift = 0.0
	else:
		_lift_tween = create_tween().set_trans(Tween.TRANS_SINE)
		_lift_tween.tween_property(self, "lift", LIFT if value else 0.0, 0.16)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var r := radius()
	var rim: Color = RIMS.get(kind, SKIN.CREAM)
	# The shadow stays on the table and softens as the chip lifts off it.
	var spread := r * 1.25 + lift
	draw_texture_rect(MATERIALS.SHADOW_CIRCLE, Rect2(center + Vector2(2, 4) - Vector2.ONE * spread, Vector2.ONE * spread * 2.0), false, Color(SHADOW, SHADOW.a - lift * 0.06))
	var top := center - Vector2(0, lift)
	draw_circle(top + Vector2(0, EDGE_DEPTH), r, EDGE)
	draw_circle(top, r, FACE)
	# Grain only: the panel grain's fibre and chalk strokes would spill off a chip.
	draw_texture_rect(MATERIALS.GRAIN, Rect2(top - Vector2.ONE * r * 0.7, Vector2.ONE * r * 1.4), false, Color(0.9, 0.95, 0.85, 0.06))
	draw_arc(top, r - 1.0, 0, TAU, 48, Color(rim, 0.95 if hovered or selected else 0.7), 2.0, true)
	draw_arc(top, r - 4.0, PI * 1.1, PI * 1.9, 24, Color(SKIN.CREAM, 0.16), 1.0, true)
	if kind == "act_rival":
		draw_arc(top, r + 3.0, 0, TAU, 56, Color(rim, 0.35), 1.0, true)
	var extent := ICON_EXTENT * (r / CHIP_RADIUS)
	# A light inner face keeps the kind glyph as bright as its legend twin.
	draw_circle(top, extent * 0.62, Color("ece6d2", 0.92))
	draw_texture_rect(icon(), Rect2(top - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false)
	if done:
		var badge := top + Vector2(r * 0.72, r * 0.62)
		draw_circle(badge, 6.0, SKIN.CREAM)
		draw_polyline(PackedVector2Array([badge + Vector2(-3, 0), badge + Vector2(-1, 2.5), badge + Vector2(3, -2.5)]), SKIN.INK, 1.6, true)
