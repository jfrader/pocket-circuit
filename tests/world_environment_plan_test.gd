extends SceneTree

## Outcome tests for WorldEnvironmentPlan (pure, deterministic, geometry-aware).
## Covers: deterministic rebuild, diverse seeds, theme isolation, hierarchy,
## clearance, overlaps, dimensions, repetition.

const Plan := preload("res://scripts/race/world_environment_plan.gd")
const CORE := preload("res://scripts/race/track_builder_core.gd")

func _make_rect_room(w: float, h: float, cx := 0.0, cy := 0.0) -> PackedVector2Array:
	var r := Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
	return PackedVector2Array([
		r.position,
		Vector2(r.position.x + r.size.x, r.position.y),
		r.position + r.size,
		Vector2(r.position.x, r.position.y + r.size.y),
	])

func _make_simple_centerline(room: PackedVector2Array, count := 64) -> PackedVector2Array:
	var b := CORE._polygon_bounds_rect(room)
	var c := b.get_center()
	var rx := b.size.x * 0.38
	var ry := b.size.y * 0.32
	var pts := PackedVector2Array()
	for i in count:
		var a := TAU * float(i) / float(count)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _make_island(centerline: PackedVector2Array) -> PackedVector2Array:
	var b := CORE._polygon_bounds_rect(centerline)
	var c := b.get_center()
	var s := minf(b.size.x, b.size.y) * 0.22
	return PackedVector2Array([
		c + Vector2(-s, -s * 0.7),
		c + Vector2( s, -s * 0.7),
		c + Vector2( s,  s * 0.7),
		c + Vector2(-s,  s * 0.7),
	])

func _mk_cand(id: String, th: Array, roles: Array, dim: Vector2, coll: String, maxr: int, cl: float, vw: float) -> Dictionary:
	return {
		"id": id,
		"themes": th,
		"roles": roles,
		"dimensions_mm": dim,
		"collision": coll,
		"max_repeats": maxr,
		"clearance_mm": cl,
		"visual_weight": vw,
	}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var failures := PackedStringArray()

	# --- base geometry + candidate fixtures ---
	var room := _make_rect_room(1800.0, 1200.0)
	var cline := _make_simple_centerline(room, 72)
	var island := _make_island(cline)
	var geo := {
		"room_polygon": room,
		"island_polygon": island,
		"centerline": cline,
		"corridor_half_width": 125.0,
	}
	var story_kitchen := {"asset_ids": []}
	var cands_mixed: Array[Dictionary] = [
		_mk_cand("kitchen_focal_mug", [&"kitchen"], [&"focal"], Vector2(140, 140), "alpha", 1, 22.0, 5.0),
		_mk_cand("kitchen_support_plate", [&"kitchen"], [&"support", &"focal"], Vector2(90, 90), "alpha", 2, 14.0, 3.0),
		_mk_cand("kitchen_micro_crumb", [&"kitchen"], [&"micro"], Vector2(18, 18), "flat", 6, 3.0, 1.0),
		_mk_cand("kitchen_boundary_knife", [&"kitchen"], [&"boundary"], Vector2(160, 22), "alpha", 3, 18.0, 2.0),
		_mk_cand("kitchen_ground_towel", [&"kitchen"], [&"ground"], Vector2(240, 180), "flat", 2, 4.0, 2.5),
		_mk_cand("kitchen_decal_spill", [&"kitchen"], [&"decal"], Vector2(70, 50), "flat", 8, 2.0, 0.8),
		_mk_cand("workshop_focal_wrench", [&"workshop"], [&"focal"], Vector2(180, 70), "alpha", 1, 20.0, 4.0),
		_mk_cand("workshop_support_hammer", [&"workshop"], [&"support"], Vector2(110, 60), "alpha", 2, 12.0, 2.0),
	]
	var story_restrict := {"asset_ids": ["kitchen_focal_mug", "kitchen_support_plate", "kitchen_micro_crumb", "kitchen_boundary_knife", "kitchen_ground_towel"]}

	# 1. DETERMINISTIC REBUILD
	var r1 := Plan.plan(&"kitchen", 424242, geo, cands_mixed, story_kitchen)
	var r2 := Plan.plan(&"kitchen", 424242, geo, cands_mixed, story_kitchen)
	if r1.hash() != r2.hash() or r1["placements"].size() != r2["placements"].size():
		failures.append("deterministic: same seed must produce identical placements")
	else:
		for i in r1["placements"].size():
			var p1: Dictionary = r1["placements"][i]
			var p2: Dictionary = r2["placements"][i]
			if p1["position"] != p2["position"] or p1["rotation"] != p2["rotation"]:
				failures.append("deterministic: position/rot drifted on rebuild")

	# 2. DIVERSE SEEDS (visibly different groups)
	var ra := Plan.plan(&"kitchen", 1001, geo, cands_mixed, story_kitchen)
	var rb := Plan.plan(&"kitchen", 1002, geo, cands_mixed, story_kitchen)
	var same_pos := true
	if ra["placements"].size() == rb["placements"].size():
		for i in ra["placements"].size():
			if ra["placements"][i]["position"].distance_to(rb["placements"][i]["position"]) > 5.0:
				same_pos = false
	else:
		same_pos = false
	if same_pos:
		failures.append("diverse seeds: different seeds must yield visibly different placements")

	# 3. THEME ISOLATION
	var rk := Plan.plan(&"kitchen", 777, geo, cands_mixed, story_kitchen)
	for p: Dictionary in rk["placements"]:
		if String(p["asset_id"]).begins_with("workshop"):
			failures.append("theme isolation: workshop asset leaked into kitchen plan")
	var rw := Plan.plan(&"workshop", 777, geo, cands_mixed, story_kitchen)
	var saw_workshop := false
	for p: Dictionary in rw["placements"]:
		if String(p["asset_id"]).begins_with("workshop"):
			saw_workshop = true
	if not saw_workshop:
		failures.append("theme isolation: workshop plan must use workshop assets when available")

	# 4. HIERARCHY (1 focal, supports in groups, restrained micros, boundary family, ground/decals)
	var rh := Plan.plan(&"kitchen", 5555, geo, cands_mixed, story_kitchen)
	var counts := {"focal": 0, "support": 0, "micro": 0, "boundary": 0, "ground": 0, "decal": 0}
	for p: Dictionary in rh["placements"]:
		var rl := String(p.get("role", ""))
		if counts.has(rl):
			counts[rl] += 1
	if counts["focal"] != 1:
		failures.append("hierarchy: exactly one focal required (got %d)" % counts["focal"])
	if counts["support"] < 2:
		failures.append("hierarchy: expected several supports (got %d)" % counts["support"])
	if counts["micro"] < 1:
		failures.append("hierarchy: expected restrained micro clusters")
	if counts["boundary"] < 2:
		failures.append("hierarchy: expected coherent sparse boundary family")

	# 5+6. CLEARANCE + OVERLAPS + DIMENSIONS + REPETITION (one pass over result)
	var rc := Plan.plan(&"kitchen", 31415, geo, cands_mixed, story_restrict)
	var placed_ids: Dictionary = {}
	var solid_rects: Array = []
	for p: Dictionary in rc["placements"]:
		var aid := String(p["asset_id"])
		placed_ids[aid] = placed_ids.get(aid, 0) + 1
		var fp: Dictionary = p["footprint"]
		var dim: Vector2 = fp["size"]
		# dimensions exact (no shrink)
		var orig_dim: Vector2 = Vector2.ZERO
		for c: Dictionary in cands_mixed:
			if String(c["id"]) == aid:
				orig_dim = c["dimensions_mm"]
				break
		if orig_dim != Vector2.ZERO and dim != orig_dim:
			failures.append("dimensions: %s shrunk or altered (used %s, declared %s)" % [aid, str(dim), str(orig_dim)])
		# clearance check
		var cl := 18.0
		for c: Dictionary in cands_mixed:
			if String(c["id"]) == aid:
				cl = float(c.get("clearance_mm", 18.0))
				break
		var sweep_ok := CORE._line_sweep_clears_footprint(cline, p["position"], dim, &"rect", float(p["rotation"]), 125.0 + cl + 2.0)
		if not sweep_ok:
			failures.append("clearance: %s violates full racing corridor" % aid)
		# record solids for overlap
		var is_flat := false
		for c: Dictionary in cands_mixed:
			if String(c["id"]) == aid and String(c.get("collision", "")) == "flat":
				is_flat = true
		if not is_flat:
			solid_rects.append({"pos": p["position"], "size": dim, "rot": float(p["rotation"])})

	# overlaps between solids
	for i in solid_rects.size():
		for j in range(i + 1, solid_rects.size()):
			var a: Dictionary = solid_rects[i]
			var b: Dictionary = solid_rects[j]
			var pa: PackedVector2Array = Plan._make_oriented_rect(a["pos"], a["size"], a["rot"])
			var pb: PackedVector2Array = Plan._make_oriented_rect(b["pos"], b["size"], b["rot"])
			if not Geometry2D.intersect_polygons(pa, pb).is_empty():
				failures.append("overlaps: solid-solid intersection detected")

	# repetition honored (use restrict story that limits some)
	for aid: String in placed_ids:
		var maxr := 99
		for c: Dictionary in cands_mixed:
			if String(c["id"]) == aid:
				maxr = int(c.get("max_repeats", 99))
				break
		if placed_ids[aid] > maxr:
			failures.append("repetition: %s exceeded max_repeats (used %d > %d)" % [aid, placed_ids[aid], maxr])

	# focal chose alt if needed (smoke: at least one placement exists for focal path)
	if rc["placements"].is_empty():
		failures.append("plan produced zero placements under restrict")

	# story restrict was honored
	for p: Dictionary in rc["placements"]:
		if String(p["asset_id"]) == "kitchen_decal_spill" or String(p["asset_id"]).begins_with("workshop"):
			failures.append("story restrict: asset outside story.asset_ids was placed")
	var reserved_geometry := geo.duplicate(true)
	var reservation := _make_rect_room(130.0, 70.0)
	reserved_geometry["reserved_polygons"] = [reservation]
	var reserved_plan := Plan.plan(&"kitchen", 424242, reserved_geometry, cands_mixed, story_kitchen)
	for placement: Dictionary in reserved_plan["placements"]:
		var polygon := Plan._make_oriented_rect(placement["position"], placement["footprint"]["size"], placement["rotation"])
		if not Geometry2D.intersect_polygons(polygon, reservation).is_empty():
			failures.append("reservations: scenery must not cover existing gate/pocket colliders")

	if not failures.is_empty():
		push_error("WORLD_ENVIRONMENT_PLAN_TEST FAIL: " + "; ".join(failures))
		quit(1)
		return
	print("WORLD_ENVIRONMENT_PLAN_TEST PASS placements=%d" % rc["placements"].size())
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	quit(0)
