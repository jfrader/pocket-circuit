extends Control

## A stop on the tabletop map: the stop kind's map icon set on a physical chip,
## with a soft contact shadow. Selection lifts it; hover brightens its rim.

const UI := preload("res://scripts/ui/run_ui.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const CHIP_RADIUS := 18.0
const BOSS_RADIUS := 20.0
const EDGE_DEPTH := 3.5
const ICON_EXTENT := 28.0
const INNER_FACE := 0.62
const FACE := Color("26332e")
const EDGE := Color("111815")
## Each kind's rim, taken from its map icon so chip, icon and legend agree.
const RIMS := {
	"race": Color("94a7bf"), "rival": Color("e04a3c"), "bench": Color("3fbf82"), "parts_van": Color("ff9d1f"),
	"lockup": Color("ffd23f"), "errand": Color("4da3e8"), "act_rival": Color("ff9d1f"),
}
const LIFT := 3.0
## Rim alpha, rim width and lamp-highlight strength by tier: a stop the player
## can go to (or stands on) leads; the rest of the act sits back a step, with a
## thinner rim as well as a dimmer one so tone is not the only cue. Hover and
## selection raise any chip to the lead rim.
const RIM_TIERS := {
	&"reachable": [0.95, 2.5, 1.0],
	&"distant": [0.55, 1.5, 0.55],
}
var kind := "race"
var reachable := false:
	set(value):
		reachable = value
		queue_redraw()
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


func rim_tier() -> StringName:
	return &"reachable" if reachable or hovered or selected else &"distant"


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
	var tier: Array = RIM_TIERS[rim_tier()]
	# The shadow stays on the table and softens as the chip lifts off it.
	var top := MATERIALS.token(self, center, r, FACE, EDGE, Color(rim, tier[0]), EDGE_DEPTH, lift, tier[1], tier[2])
	# Grain only: the panel grain's fibre and chalk strokes would spill off a chip.
	draw_texture_rect(MATERIALS.GRAIN, Rect2(top - Vector2.ONE * r * 0.7, Vector2.ONE * r * 1.4), false, Color(0.9, 0.95, 0.85, 0.06))
	if kind == "act_rival":
		draw_arc(top, r + 3.0, 0, TAU, 56, Color(rim, 0.35), 1.0, true)
	var extent := ICON_EXTENT * (r / CHIP_RADIUS)
	# A light inner face keeps the kind glyph as bright as its legend twin; it is
	# shaded like the chip, lit upper left, so the two read as one piece.
	var inner := extent * INNER_FACE
	draw_circle(top, inner, Color("ece6d2", 0.92))
	draw_arc(top, inner - 1.5, PI * -0.1, PI * 0.8, 24, Color(0, 0, 0, 0.14), 3.0, true)
	draw_arc(top, inner - 1.0, PI * 1.05, PI * 1.55, 20, Color(MATERIALS.TOKEN_HIGHLIGHT, 0.9), 1.5, true)
	draw_texture_rect(icon(), Rect2(top - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false)
	if done:
		var badge := top + Vector2(r * 0.72, r * 0.62)
		draw_circle(badge, 6.0, SKIN.CREAM)
		draw_polyline(PackedVector2Array([badge + Vector2(-3, 0), badge + Vector2(-1, 2.5), badge + Vector2(3, -2.5)]), SKIN.INK, 1.6, true)
