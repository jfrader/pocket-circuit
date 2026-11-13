extends RefCounted
## The night's only authored route. Anchors describe two opposing boiler-room
## folds, a diagonal pressure climb and an offset finish shelf; no route RNG
## or generated route program is used.

const ROUTE_ID := "basement_boiler_run_v1"
const THEME := &"basement"
const LENGTH_TIER := "long"
const MATERIAL_SEED := 2474
const GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const ROOM := Rect2(-2500, -1800, 5000, 3400)
const ANCHORS := [
	Vector2(-2000, 900), Vector2(-2000, -900),
	Vector2(-1200, -900), Vector2(-1200, 150),
	Vector2(-400, 150), Vector2(-400, -900),
	Vector2(150, -900), Vector2(650, -1300),
	Vector2(1300, -1300), Vector2(2000, -650), Vector2(2000, 900),
	Vector2(1100, 900), Vector2(1100, -100),
	Vector2(350, -100), Vector2(350, 900),
	Vector2(-650, 1100), Vector2(-1400, 1100),
]
const CORNER_RADII := [260.0, 260.0, 210.0, 210.0, 210.0, 210.0, 240.0, 240.0, 260.0, 280.0, 300.0, 230.0, 230.0, 230.0, 230.0, 260.0, 260.0]


static func is_finale(act: int, node: Dictionary) -> bool:
	return act == RunSession.FINAL_ACT and String(node.get("type", "")) == "act_rival"


static func identity() -> Dictionary:
	return {"authored_route": ROUTE_ID, "theme": String(THEME), "room": "wide", "seed": MATERIAL_SEED, "reverse": false, "length_tier": LENGTH_TIER, "display_name": "THE BASEMENT"}


static func event() -> Dictionary:
	var result := identity()
	result.merge({"circuit": "authored", "name": result["display_name"], "act": RunSession.FINAL_ACT, "laps": 3, "race_format": "circuit"})
	return result


static func controls() -> PackedVector2Array:
	var points := GRAMMAR.round_corners(PackedVector2Array(ANCHORS), PackedFloat32Array(CORNER_RADII))
	# Start halfway down the west straight, with room for all six grid slots.
	var start := 0
	for index in points.size():
		if points[index].distance_squared_to(Vector2(-2000, 0)) < points[start].distance_squared_to(Vector2(-2000, 0)):
			start = index
	var ordered := PackedVector2Array()
	for index in points.size():
		ordered.append(points[(start + index) % points.size()])
	return ordered


static func spec(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	result.merge({
		"root_name": "TheBasement", "controls": controls(), "authored_route": ROUTE_ID,
		"length_tier": LENGTH_TIER, "material_seed": MATERIAL_SEED, "dressing_seed": MATERIAL_SEED,
		"story_kit": {"id": ROUTE_ID}, "environment_theme": THEME,
		"edge_texture": "res://assets/textures/world_materials/basement_concrete.png",
		"highlight": Color("343b40"), "island": Color("252d30"),
		"rim_dark": Color("141c20"), "rim_highlight": Color("8a9791"),
		"ambient_props": [], "gate_props": [], "corridor_patterns": [],
		"signature_hazards": [{
			"id": "BoilerLeak", "name": &"boiler leak", "grip": 0.48, "speed": 0.82,
			"points": PackedVector2Array([Vector2(1000, -20), Vector2(1200, -20), Vector2(1200, 300), Vector2(1000, 300)]),
			"warning_position": Vector2(1020, 440), "label": "WET FLOOR",
			"color": Color(0.28, 0.68, 0.78, 0.65),
			"decal": "res://assets/textures/ground_dressing/basement_puddle.png",
		}],
	}, true)
	result.erase("gate_fractions")
	return result
