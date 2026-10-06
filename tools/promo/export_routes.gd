extends SceneTree
## Writes $PROMO_OUT/routes.json: real centerlines of generated circuits across
## every theme, length tier and direction, for the circuit wall.

const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const THEMES: Array[String] = ["kitchen", "workshop", "office"]
const TIERS: Array[String] = ["compact", "standard", "long", "endurance"]
const ROUTE_COUNT := 120
const MAX_ATTEMPTS := 400
const POINTS_PER_ROUTE := 220
const RNG_SEED := 20261006
const SEED_MAX := 999999


func _initialize() -> void:
	var out_dir := OS.get_environment("PROMO_OUT")
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var routes := []
	var attempt := 0
	while routes.size() < ROUTE_COUNT and attempt < MAX_ATTEMPTS:
		attempt += 1
		var seed := rng.randi_range(0, SEED_MAX)
		var theme := StringName(THEMES[attempt % THEMES.size()])
		var tier: String = TIERS[(attempt / THEMES.size()) % TIERS.size()]
		var reverse := attempt % 2 == 0
		var identity := IDS.create(theme, IDS.room_for_route_seed(seed), seed, reverse, 0, "", "", {}, tier, IDS.DEFAULT_ROAD_WIDTH, "circuit")
		if identity.is_empty():
			continue
		var prepared := TRACK_BUILDER.prepare_route(theme, StringName(identity["room"]), int(identity["sub_seeds"]["route"]), IDS.generation_options(identity))
		if prepared.is_empty():
			continue
		var centerline: PackedVector2Array = prepared["centerline"]
		var points := []
		var step := maxi(1, centerline.size() / POINTS_PER_ROUTE)
		for index in range(0, centerline.size(), step):
			points.append([snappedf(centerline[index].x, 0.1), snappedf(centerline[index].y, 0.1)])
		routes.append({"name": identity["display_name"], "theme": String(theme), "tier": tier, "seed": seed, "reverse": reverse, "points": points})
	var file := FileAccess.open(out_dir.path_join("routes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(routes))
	file.close()
	print("PROMO routes ", routes.size())
	quit()
