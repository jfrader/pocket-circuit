extends SceneTree
## Prototype sampler (GURI-1371): dumps generated centerlines per room for one tier.
## PC_TIER=<tier> PC_N=<seeds per room> PC_OUT=/abs/path.json godot --headless --path . --script res://tools/sample_route_shapes.gd

const WORLD_SCALE := 1.75
const ROOMS := ["classic", "wide", "tall", "long", "square", "el"]
var TIERS := [OS.get_environment("PC_TIER")]
var SEEDS := int(OS.get_environment("PC_N"))


func _initialize() -> void:
	var out := []
	var programs := {}
	for tier: String in TIERS:
		for room: String in ROOMS:
			var polygon: PackedVector2Array = TrackBuilderCore.ROOM_SHAPES[StringName(room)]
			var profile := TrackSeedGen.length_profile(StringName(tier))
			var scale := float(profile.get("room_scale", 1.0))
			var scaled := PackedVector2Array()
			for p: Vector2 in polygon:
				scaled.append(p * scale)
			var params := {
				"margin": 190.0, "min_self_distance": 320.0,
				"min_loop_length": 1900.0 * WORLD_SCALE, "room_polygon": scaled,
				"room_shape": StringName(room), "length_tier": StringName(tier),
			}
			match room:
				"el": params["min_loop_length"] = 1500.0 * WORLD_SCALE
				"long": params["min_loop_length"] = 2000.0 * WORLD_SCALE
				"square": params["min_loop_length"] = 2200.0 * WORLD_SCALE
			for seed in range(1, SEEDS + 1):
				var gen := TrackSeedGen.generate_with_retries(seed * 7919, Rect2(-940, -540, 1880, 1080), params)
				var pts: PackedVector2Array = gen["points"]
				var line := TrackSeedGen.centerline_checkpoints(pts) if not pts.is_empty() else PackedVector2Array()
				var key := "%s/%s" % [tier, String(gen.get("route_program", "none"))]
				programs[key] = int(programs.get(key, 0)) + 1
				printerr("done %s %s %d %s" % [tier, room, seed, String(gen.get("route_program", "none"))])
				out.append({
					"tier": tier, "room": room, "seed": seed * 7919,
					"program": String(gen.get("route_program", "none")),
					"attempt": int(gen.get("attempt", -1)), "fallback": bool(gen.get("fallback", true)),
					"length": float(gen.get("length", 0.0)),
					"reason": String(gen.get("fallback_reason", gen.get("reason", ""))),
					"room_polygon": _flat(scaled), "line": _flat(line),
				})
	var f := FileAccess.open(OS.get_environment("PC_OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print(JSON.stringify(programs))
	quit()


func _flat(points: PackedVector2Array) -> Array:
	var a := []
	for p: Vector2 in points:
		a.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return a
