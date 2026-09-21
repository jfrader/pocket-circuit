class_name TrackSeedGen
## Deterministic procedural circuit generation from bounded macro-route grammar.
## Family, length, and route-program selection use independent hash streams.

const ROUTE_GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const SECTIONS := preload("res://scripts/race/track_route_sections.gd")
const CURVE_SAMPLING := preload("res://scripts/race/track_curve_sampling.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")

const SAMPLE_COUNT := 260
const HALF_WIDTH := 125.0
const CORRIDOR_CLEARANCE := HALF_WIDTH + 10.0
const SPLINE_GUARD := 12.0
const MAX_VARIANTS := 12
const WORLD_SCALE := 1.75
const MIN_SETUP_DISTANCE := 450.0
# A v1 vehicle sweeps roughly 22u around its center. Requiring the full 125u
# half-corridor plus that hull prevents a legal centerline from demanding a
# near-pivot turn while preserving the constrained L-room realization.
const VEHICLE_HULL_RADIUS := 22.0
const MIN_DRIVE_RADIUS := HALF_WIDTH + VEHICLE_HULL_RADIUS
const FILLET_RADIUS_MARGIN := 24.0
const STRAIGHT_CONTROL_SPACING := 110.0
const LITERAL_STRAIGHT_HEADING_TOLERANCE := 0.04
const SETUP_STRAIGHTNESS := 0.985
const BYPASS_MIN_ARC := 500.0
const BYPASS_MAX_ARC := 3000.0
const BYPASS_MIN_SAVING := 220.0
const BYPASS_MIN_RATIO := 1.40

# Seed-stable labels only. Geometry comes from TrackRouteGrammar programs, not
# these names. Do not reorder: championship identity hashes this list.
const FAMILY_NAMES: Array[StringName] = [
	&"speed_loop",
	&"kidney",
	&"dogbone",
	&"broad_triangle",
	&"offset_s",
	&"deep_notch",
]

const FAMILY_SALT := 0x13579BDF
const LENGTH_SALT := 0x2468ACE
const VARIANT_SALT := 0x51A7E3D
const RHYTHM_SALT := 0x4A71C9D
const ROUTE_SALT := 0x2D91F3B


static func generate_with_retries(seed: int, room_rect: Rect2, params: Dictionary = {}) -> Dictionary:
	# Attempts vary only the requested seed's family parameters. The caller must
	# never receive a neighboring seed because seed identity is player-facing.
	return _generate_result(seed, room_rect, params)


static func generate(seed: int, room_rect: Rect2, params: Dictionary = {}) -> PackedVector2Array:
	return _generate_result(seed, room_rect, params)["points"] as PackedVector2Array


static func length_profile(tier: StringName) -> Dictionary:
	return GENERATED_RULES.length_profile(String(tier))


static func centerline_checkpoints(controls: PackedVector2Array) -> PackedVector2Array:
	return _sample_centerline(controls)


static func gameplay_metrics(controls: PackedVector2Array) -> Dictionary:
	var centerline := _sample_centerline(controls)
	if centerline.is_empty():
		return {}
	var bypass := _best_complex_bypass(centerline)
	var setup_straight_count := _setup_straight_count(centerline)
	var literal_straight_count := _literal_straight_count(centerline)
	return {
		"length": _polyline_length(centerline),
		"minimum_turn_radius": _minimum_turn_radius(centerline),
		"has_setup_straight": setup_straight_count > 0,
		"setup_straight_count": setup_straight_count,
		"literal_straight_count": literal_straight_count,
		"complex_bypass": bypass,
		"route_sequence": normalized_route_sequence(controls),
	}


static func normalized_route_sequence(controls: PackedVector2Array) -> String:
	return _canonical_symbol_sequence(_raw_turn_tokens(controls))


static func raw_turn_mix(controls: PackedVector2Array) -> Vector2i:
	var left := 0
	var right := 0
	for token: String in _raw_turn_tokens(controls):
		if token.begins_with("L"):
			left += 1
		elif token.begins_with("R"):
			right += 1
	return Vector2i(left, right)


static func _raw_turn_tokens(controls: PackedVector2Array) -> Array[String]:
	var centerline := _sample_centerline(controls)
	var symbols: Array[String] = []
	if centerline.is_empty():
		return symbols
	var span := 5
	for index in range(0, centerline.size(), span):
		var incoming := centerline[posmod(index - span, centerline.size())].direction_to(centerline[index])
		var outgoing := centerline[index].direction_to(centerline[(index + span) % centerline.size()])
		var angle := incoming.angle_to(outgoing)
		if absf(angle) < 0.10:
			symbols.append("S")
		else:
			var strength := "1" if absf(angle) < 0.28 else ("2" if absf(angle) < 0.52 else "3")
			symbols.append(("L" if angle > 0.0 else "R") + strength)
	return symbols


static func _canonical_symbol_sequence(symbols: Array[String]) -> String:
	var mirrored: Array[String] = []
	var reversed: Array[String] = []
	var reversed_mirrored: Array[String] = []
	for symbol: String in symbols:
		mirrored.append(_swap_turn_symbol(symbol))
	for index in range(symbols.size() - 1, -1, -1):
		reversed.append(_swap_turn_symbol(symbols[index]))
		reversed_mirrored.append(symbols[index])
	var best := ""
	for variant: Array[String] in [symbols, mirrored, reversed, reversed_mirrored]:
		for offset in variant.size():
			var ordered := PackedStringArray()
			for index in variant.size():
				ordered.append(variant[(offset + index) % variant.size()])
			var candidate := ".".join(ordered)
			if best.is_empty() or candidate < best:
				best = candidate
	return best


static func _swap_turn_symbol(symbol: String) -> String:
	if symbol.begins_with("L"):
		return "R" + symbol.substr(1)
	if symbol.begins_with("R"):
		return "L" + symbol.substr(1)
	return symbol


static func _generate_result(seed: int, room_rect: Rect2, params: Dictionary) -> Dictionary:
	var family_index := posmod(_hash32(seed ^ FAMILY_SALT), FAMILY_NAMES.size())
	var family: StringName = FAMILY_NAMES[family_index]
	var tier := StringName(params.get("length_tier", &"standard"))
	var instrument_rejections := bool(params.get("instrument_rejections", false))
	var rejection_attempts: Array[Dictionary] = []
	var rejection_counts: Dictionary = {}
	var profile := length_profile(tier)
	if profile.is_empty():
		var e = _empty_result(seed, family)
		e["reason"] = "profile empty"
		_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, -1, &"setup", &"invalid_profile", e["reason"])
		return _with_generation_diagnostics(e, params, tier, instrument_rejections, rejection_attempts, rejection_counts)
	var length_roll := _hash_unit(seed, LENGTH_SALT)
	var target_length := lerpf(float(profile["min_length"]), float(profile["max_length"]), length_roll)
	var configured_max := float(params.get("max_loop_length", 0.0))
	if configured_max > 0.0:
		target_length = minf(target_length, configured_max)
	var max_length := float(profile["max_length"])

	var room_polygon: PackedVector2Array = params.get("room_polygon", PackedVector2Array())
	var room_shape := StringName(params.get("room_shape", &""))
	var source_rect := _generation_rect(room_rect, params, room_polygon)
	var requested_margin := float(params.get("margin", 150.0))
	
	var width_amplitude := float(params.get("width_amplitude", 0.0))
	var forced_half := float(params.get("forced_half_width", 0.0))
	var eff_half := HALF_WIDTH
	if width_amplitude > 0.0:
		eff_half = 240.0
	elif forced_half > 0.0:
		eff_half = forced_half
	var eff_clearance := eff_half + 10.0

	var centerline_margin := maxf(requested_margin, eff_clearance)
	var usable_rect := source_rect.grow(-centerline_margin).grow(-SPLINE_GUARD)
	if usable_rect.size.x < eff_half * 2.0 or usable_rect.size.y < eff_half * 2.0:
		var e = _empty_result(seed, family)
		e["reason"] = "usable rect too small"
		_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, -1, &"setup", &"room_too_small", e["reason"])
		return _with_generation_diagnostics(e, params, tier, instrument_rejections, rejection_attempts, rejection_counts)

	var requested_self_distance := maxf(float(params.get("min_self_distance", 250.0)), eff_half * 2.0)
	# A narrow room cannot honor an arbitrarily large requested branch gap after
	# reserving the corridor and wall margin. Keep the full corridor clear while
	# accepting that physical maximum instead of rejecting every candidate.
	var physical_self_distance := maxf(eff_half * 2.0, minf(usable_rect.size.x, usable_rect.size.y) * 0.55)
	var min_self_distance := minf(requested_self_distance, physical_self_distance)
	var room_check_margin := maxf(float(params.get("room_check_margin", 0.0)), eff_clearance)
	var minimum_length := float(params.get("min_loop_length", 1900.0 * WORLD_SCALE))
	# Large tiers honor their band floor as a validation minimum so a compact
	# program cannot slip in below the selected band.
	if tier != &"standard":
		minimum_length = maxf(minimum_length, float(profile["min_length"]))
	var last_reason := "no candidate"
	# Profiles and the straight motif now run on every room; the shared sampler
	# plus the corridor-boundary simplification keep long/tall loops valid, and
	# the whole-loop validation still rejects any candidate that would tip a
	# room's aspect or clearance, so no whole-category silence is needed.
	var decorate_enabled := width_amplitude <= 0.001 and forced_half <= 0.0
	# The standard tier keeps its 0.78 aesthetic fit floor; non-standard tiers fit
	# from the physical branch-gap and corner-radius constraints only.
	var fit_floor := 0.78 if tier == &"standard" else 0.0

	for attempt in MAX_VARIANTS:
		var attempt_pockets: Array = []
		var attempt_profiles: Array = []
		var generation_rect := usable_rect
		var use_el_controls := room_shape == &"el"
		if use_el_controls and tier == &"compact":
			# Compact EL occupies one safe arm sub-rect (4-6k dogleg/U) rather than
			# the whole L perimeter, which cannot shrink that far.
			generation_rect = _el_compact_bounds(room_polygon, seed, attempt)
			if generation_rect.size.x < 1.0:
				generation_rect = usable_rect
			use_el_controls = false
		# The marathon L carries a combed fold on one arm so it is not a bare
		# perimeter; every smaller tier keeps the plain seeded L footprint.
		var el_folded := use_el_controls and tier == &"marathon"
		var el_program: StringName = &"el_folded" if el_folded else &"el_safe"
		var controls := _el_controls(family, seed, attempt, source_rect, target_length, min_self_distance, float(profile["room_scale"]), el_folded) \
			if use_el_controls else _family_controls(family, family, seed, attempt, generation_rect, target_length, max_length, min_self_distance, fit_floor, attempt_pockets, attempt_profiles, decorate_enabled, tier)
		var validation := _validate_controls(
			controls,
			source_rect,
			room_polygon,
			room_check_margin,
			min_self_distance,
			minimum_length,
			width_amplitude,
			seed,
			forced_half
		)
		last_reason = String(validation.get("reason", "unknown"))
		if not bool(validation["valid"]):
			_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, attempt, &"primary", _rejection_category(last_reason), last_reason)
			continue
		if bool(validation["valid"]):
			var ordered_controls := _reorder_to_longest_straight(controls)
			var ordered_validation := _validate_controls(
				ordered_controls,
				source_rect,
				room_polygon,
				room_check_margin,
				min_self_distance,
				minimum_length, width_amplitude, seed, forced_half
			)
			if not bool(ordered_validation["valid"]):
				last_reason = "post-order " + String(ordered_validation.get("reason", "unknown"))
				var post_order_category := StringName("post_order_" + String(_rejection_category(String(ordered_validation.get("reason", "unknown")))))
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, attempt, &"primary", post_order_category, last_reason)
				continue
			var motif := {"controls": ordered_controls, "motifs": [], "rejections": [], "length": float(ordered_validation["length"])}
			if decorate_enabled:
				motif = _apply_straight_motif(
					ordered_controls, source_rect, room_polygon, room_check_margin,
					min_self_distance, minimum_length, max_length, float(ordered_validation["length"])
				)
			var final_controls: PackedVector2Array = motif["controls"]
			if float(motif["length"]) > max_length or float(motif["length"]) < minimum_length:
				last_reason = "composed route outside requested length band"
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, attempt, &"primary", &"length_band", last_reason)
				continue
			if tier == &"standard" and not _room_aspect_ok(final_controls, room_shape):
				last_reason = "room aspect tipped by profile/motif"
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, attempt, &"primary", &"room_aspect", last_reason)
				continue
			var result := {
				"points": final_controls,
				"seed": seed,
				"family": family,
				"length": float(motif["length"]),
				"target_length": target_length,
				"length_tier": tier,
				"length_profile": String(profile["id"]),
				"attempt": attempt,
				"fallback": false,
				"pockets": _detect_pockets(final_controls),
				"realization": el_program if room_shape == &"el" and tier != &"compact" else family,
				"route_recipe": el_program if room_shape == &"el" and tier != &"compact" else _route_name(seed, attempt, target_length, tier),
				"route_program": el_program if room_shape == &"el" and tier != &"compact" else _route_program_name(seed, attempt, target_length, tier),
				"route_sequence": normalized_route_sequence(final_controls),
				"corner_profiles": _merge_profile_counts(attempt_profiles),
				"motifs": motif["motifs"],
				"motif_rejections": motif["rejections"],
			}
			return _with_generation_diagnostics(result, params, tier, instrument_rejections, rejection_attempts, rejection_counts)

	var family_reason := last_reason
	# The fallback is deterministic and never changes the requested seed or its
	# selected family metadata. EL rooms retain their dedicated L-safe route.
	for fallback_attempt in 4:
		var fallback_pockets: Array = []
		var fallback_profiles: Array = []
		var fallback_minimum := minf(minimum_length, target_length * 0.72) if tier == &"standard" else minimum_length
		var generation_rect := usable_rect
		var use_el_safe := room_shape == &"el"
		if use_el_safe and tier == &"compact":
			generation_rect = _el_compact_bounds(room_polygon, seed, MAX_VARIANTS + fallback_attempt)
			if generation_rect.size.x < 1.0:
				generation_rect = usable_rect
			use_el_safe = false
		var controls := _el_safe_controls(family, seed, fallback_attempt, source_rect, target_length, min_self_distance, float(profile["room_scale"])) \
			if use_el_safe else _family_controls(&"conservative", family, seed, fallback_attempt, generation_rect, target_length, max_length, min_self_distance, fit_floor, fallback_pockets, fallback_profiles, decorate_enabled, tier)
		var validation := _validate_controls(
			controls,
			source_rect,
			room_polygon,
			room_check_margin,
			min_self_distance,
			fallback_minimum,
			width_amplitude,
			seed,
			forced_half
		)
		last_reason = String(validation.get("reason", "unknown"))
		if not bool(validation["valid"]):
			_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, MAX_VARIANTS + fallback_attempt, &"fallback", _rejection_category(last_reason), last_reason)
			continue
		if bool(validation["valid"]):
			var ordered_controls := _reorder_to_longest_straight(controls)
			var ordered_validation := _validate_controls(
				ordered_controls,
				source_rect,
				room_polygon,
				room_check_margin,
				min_self_distance,
				fallback_minimum, width_amplitude, seed, forced_half
			)
			if not bool(ordered_validation["valid"]):
				last_reason = "post-order " + String(ordered_validation.get("reason", "unknown"))
				var post_order_category := StringName("post_order_" + String(_rejection_category(String(ordered_validation.get("reason", "unknown")))))
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, MAX_VARIANTS + fallback_attempt, &"fallback", post_order_category, last_reason)
				continue
			var motif := {"controls": ordered_controls, "motifs": [], "rejections": [], "length": float(ordered_validation["length"])}
			if decorate_enabled:
				motif = _apply_straight_motif(
					ordered_controls, source_rect, room_polygon, room_check_margin,
					min_self_distance, fallback_minimum, max_length, float(ordered_validation["length"])
				)
			var final_controls: PackedVector2Array = motif["controls"]
			if float(motif["length"]) > max_length or float(motif["length"]) < fallback_minimum:
				last_reason = "fallback outside requested length band"
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, MAX_VARIANTS + fallback_attempt, &"fallback", &"length_band", last_reason)
				continue
			if tier == &"standard" and not _room_aspect_ok(final_controls, room_shape):
				last_reason = "room aspect tipped by profile/motif"
				_record_rejection(instrument_rejections, rejection_attempts, rejection_counts, MAX_VARIANTS + fallback_attempt, &"fallback", &"room_aspect", last_reason)
				continue
			var result := {
				"points": final_controls,
				"seed": seed,
				"family": family,
				"length": float(motif["length"]),
				"target_length": target_length,
				"length_tier": tier,
				"length_profile": String(profile["id"]),
				"attempt": MAX_VARIANTS + fallback_attempt,
				"fallback": true,
				"pockets": _detect_pockets(final_controls),
				"realization": &"el_safe" if room_shape == &"el" and tier != &"compact" else &"technical_perimeter",
				"route_recipe": &"el_safe" if room_shape == &"el" and tier != &"compact" else &"technical_perimeter",
				"route_program": &"el_safe" if room_shape == &"el" and tier != &"compact" else &"technical_perimeter",
				"route_sequence": normalized_route_sequence(final_controls),
				"corner_profiles": _merge_profile_counts(fallback_profiles),
				"motifs": motif["motifs"],
				"motif_rejections": motif["rejections"],
				"fallback_reason": family_reason,
			}
			return _with_generation_diagnostics(result, params, tier, instrument_rejections, rejection_attempts, rejection_counts)
	var empty := _empty_result(seed, family)
	empty["reason"] = last_reason
	return _with_generation_diagnostics(empty, params, tier, instrument_rejections, rejection_attempts, rejection_counts)


static func _empty_result(seed: int, family: StringName) -> Dictionary:
	return {
		"points": PackedVector2Array(),
		"seed": seed,
		"family": family,
		"length": 0.0,
		"target_length": 0.0,
		"attempt": -1,
		"fallback": true,
		"realization": &"none",
		"route_recipe": &"none",
		"route_program": &"none",
		"route_sequence": "",
	}


static func _record_rejection(
	enabled: bool,
	attempts: Array[Dictionary],
	counts: Dictionary,
	attempt: int,
	phase: StringName,
	category: StringName,
	reason: String
) -> void:
	if not enabled:
		return
	attempts.append({
		"attempt": attempt,
		"phase": String(phase),
		"category": String(category),
		"reason": reason,
	})
	counts[String(category)] = int(counts.get(String(category), 0)) + 1


static func _with_generation_diagnostics(
	result: Dictionary,
	params: Dictionary,
	tier: StringName,
	enabled: bool,
	attempts: Array[Dictionary],
	counts: Dictionary
) -> Dictionary:
	if enabled:
		result["generation_diagnostics"] = {
			"room": String(params.get("room_shape", "")),
			"tier": String(tier),
			"seed": int(result.get("seed", -1)),
			"rejections": attempts,
			"rejection_counts": counts,
		}
	return result


static func _rejection_category(reason: String) -> StringName:
	if reason == "too few controls":
		return &"proposal_geometry"
	if reason == "self intersection":
		return &"self_intersection"
	if reason.begins_with("self distance"):
		return &"self_distance"
	if reason.begins_with("corridor offset"):
		return &"corridor_offset"
	if reason == "outside source rect":
		return &"source_bounds"
	if reason == "outside room margin" or reason == "variable-width road edge outside room polygon":
		return &"room_clearance"
	if reason == "below minimum length":
		return &"minimum_length"
	if reason.begins_with("only") and reason.contains("setup straight"):
		return &"setup_straights"
	if reason.begins_with("only") and reason.contains("literal straight"):
		return &"literal_straights"
	if reason.begins_with("driveable chord"):
		return &"driveable_bypass"
	if reason.begins_with("turn radius") or reason == "local turn radius < w_local + hull":
		return &"turn_radius"
	if reason == "local branch w_a + w_b + gap violated":
		return &"branch_spacing"
	return &"validation_other"


static func _generation_rect(room_rect: Rect2, params: Dictionary, room_polygon: PackedVector2Array) -> Rect2:
	if not room_polygon.is_empty():
		return _points_rect(room_polygon)
	return room_rect


static func _family_controls(
	template_family: StringName,
	_rhythm_family: StringName,
	seed: int,
	attempt: int,
	usable_rect: Rect2,
	target_length: float,
	max_length: float,
	min_self_distance: float,
	fit_floor: float = 0.78,
	pockets: Array = [],
	profile_summary: Array = [],
	profiles_enabled: bool = true,
	tier: StringName = &""
) -> PackedVector2Array:
	var definition := {} if template_family == &"conservative" else _route_definition(seed, attempt, target_length, tier)
	if template_family != &"conservative":
		var tall := usable_rect.size.y > usable_rect.size.x
		var size := Vector2(usable_rect.size.y, usable_rect.size.x) if tall else usable_rect.size
		var bias := clampf(inverse_lerp(8500.0, 9600.0, target_length), 0.0, 1.0)
		var rhythm_seed := _hash32(seed ^ (attempt * RHYTHM_SALT))
		if tier == &"marathon":
			definition = ROUTE_GRAMMAR.construct_marathon(_route_index(seed, attempt, tier), rhythm_seed, bias, Rect2(-size * 0.5, size))
		else:
			definition = ROUTE_GRAMMAR.construct(_route_index(seed, attempt), rhythm_seed, bias, Rect2(-size * 0.5, size))
		var vertices: PackedVector2Array = definition["anchors"]
		for i in vertices.size():
			vertices[i] = usable_rect.get_center() + (vertices[i].rotated(PI * 0.5) if tall else vertices[i])
		var rounded := _round_controls(vertices, definition["radii"], rhythm_seed if profiles_enabled else -1)
		var controls: PackedVector2Array = rounded["controls"]
		if controls.is_empty():
			return controls
		var full_line := _sample_centerline(controls)
		var clearance := _minimum_branch_distance(full_line, min_self_distance)
		# The standard tier keeps its 0.78 aesthetic floor; large/compact tiers fit
		# from the physical branch-gap and corner-radius constraints only, so a
		# wide full perimeter can shrink into its band instead of being clamped.
		var minimum_scale := maxf(fit_floor, min_self_distance / maxf(clearance, 1.0)) if clearance < INF else fit_floor
		for i in vertices.size():
			var previous := vertices[posmod(i - 1, vertices.size())]
			var next := vertices[(i + 1) % vertices.size()]
			var half_turn := absf(previous.direction_to(vertices[i]).angle_to(vertices[i].direction_to(next))) * 0.5
			var available := minf(previous.distance_to(vertices[i]), vertices[i].distance_to(next)) * 0.48
			minimum_scale = maxf(minimum_scale, (ROUTE_GRAMMAR.CORNER_RADIUS + 1.0) * tan(half_turn) / available)
		if minimum_scale > 1.0:
			return PackedVector2Array()
		var scale := clampf(target_length / maxf(_polyline_length(full_line), 1.0), minimum_scale, 1.0)
		if scale < 0.999:
			for i in vertices.size():
				vertices[i] = usable_rect.get_center() + (vertices[i] - usable_rect.get_center()) * scale
			rounded = _round_controls(vertices, definition["radii"], rhythm_seed if profiles_enabled else -1)
			controls = rounded["controls"]
		if _polyline_length(_sample_centerline(controls)) > max_length:
			return PackedVector2Array()
		pockets.append_array(_detect_pockets(vertices))
		profile_summary.append(rounded["profiles"])
		return controls
	var anchors := _technical_perimeter_template() if template_family == &"conservative" else (definition.get("anchors", PackedVector2Array()) as PackedVector2Array)
	if anchors.is_empty():
		return PackedVector2Array()

	# Templates are authored horizontally. Rotate them before fitting a tall room
	# so dogbones become vertical dogbones, not stretched horizontal circles.
	var orientation := 0.0
	var heading_sign := -1.0 if _hash_unit(seed, ROUTE_SALT + 0x91 + attempt * 17) < 0.5 else 1.0
	var heading_roll := _hash_unit(seed, ROUTE_SALT + 0xB3 + attempt * 29)
	if usable_rect.size.y > usable_rect.size.x * 1.12:
		orientation = PI * 0.5 + heading_sign * lerpf(0.08, 0.20, heading_roll)
	elif maxf(usable_rect.size.x, usable_rect.size.y) < minf(usable_rect.size.x, usable_rect.size.y) * 1.12:
		orientation = float(posmod(_hash32(seed ^ (VARIANT_SALT + 0x37)), 4)) * PI * 0.5 + heading_sign * lerpf(0.16, 0.42, heading_roll)
	elif usable_rect.size.x > usable_rect.size.y * 1.75:
		orientation = heading_sign * lerpf(0.06, 0.14, heading_roll)
	else:
		orientation = heading_sign * lerpf(0.10, 0.26, heading_roll)
	var mirror := -1.0 if _hash_unit(seed, VARIANT_SALT + 7) < 0.5 else 1.0
	for index in anchors.size():
		var point := anchors[index]
		point.x *= mirror
		anchors[index] = point.rotated(orientation)
	# Fit the macro vertices first, then build world-space quadratic fillets.
	# Collinear controls remain between fillets so Catmull sampling cannot turn a
	# declared straight into the blanket-smoothed bends used by the old generator.
	var mapped_vertices := _map_to_rect(anchors, usable_rect)
	if mapped_vertices.is_empty():
		return PackedVector2Array()
	# Per-corner fillet radii: base +24 margin plus 0..40 roll gives tight hairpins (near 147-171)
	# next to big sweepers on same route; tangent clamp still self-limits on short edges.
	var radii := _per_corner_fillet_radii(seed, attempt, mapped_vertices.size())
	var full_controls := _filleted_controls(mapped_vertices, radii)
	var full_centerline := _sample_centerline(full_controls)
	var full_length := _polyline_length(full_centerline)
	if full_length < 1.0:
		return PackedVector2Array()

	# Keep enough of the full-size candidate to preserve nonlocal clearance. This
	# lets short length rolls stay within their family instead of collapsing a
	# waist and falling through to a generic loop.
	var minimum_scale := maxf(0.62, 285.0 / minf(usable_rect.size.x, usable_rect.size.y))
	var full_clearance := _minimum_branch_distance(full_centerline, min_self_distance)
	if full_clearance < INF:
		minimum_scale = maxf(minimum_scale, minf(1.0, min_self_distance / maxf(full_clearance, 1.0)))
	var retry_ceiling := maxf(minimum_scale, 1.0 - float(attempt) * 0.012)
	var length_scale := clampf(target_length / full_length, minimum_scale, retry_ceiling)
	var center := usable_rect.get_center()
	var slack := usable_rect.size * (1.0 - length_scale) * 0.18
	var offset := Vector2(
		(_hash_unit(seed, LENGTH_SALT + 31) * 2.0 - 1.0) * slack.x,
		(_hash_unit(seed, LENGTH_SALT + 47) * 2.0 - 1.0) * slack.y
	)
	for index in mapped_vertices.size():
		mapped_vertices[index] = center + (mapped_vertices[index] - center) * length_scale + offset
	pockets.append_array(_detect_pockets(mapped_vertices))
	return _filleted_controls(mapped_vertices, radii)


## Round grammar vertices with seeded two-arc profiles, falling back to plain
## circular fillets when the profiles perturb the loop into self-intersection or
## a folded corridor. Profiles are therefore compositional: they never invalidate
## a route that the circular baseline would accept.
static func _round_controls(vertices: PackedVector2Array, radii: PackedFloat32Array, rhythm_seed: int) -> Dictionary:
	var rounded := ROUTE_GRAMMAR.round_corners_profiled(vertices, radii, rhythm_seed)
	if (rounded["controls"] as PackedVector2Array).is_empty():
		return rounded
	if not _profile_geometry_safe(rounded["controls"]):
		return ROUTE_GRAMMAR.round_corners_profiled(vertices, radii, -1)
	return rounded


static func _profile_geometry_safe(controls: PackedVector2Array) -> bool:
	var centerline := _sample_centerline(controls)
	return not _has_self_intersection(centerline)


static func _filleted_controls(vertices: PackedVector2Array, desired_radii: Variant) -> PackedVector2Array:
	if vertices.size() < 3:
		return PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	if typeof(desired_radii) == TYPE_FLOAT or typeof(desired_radii) == TYPE_INT:
		for i in vertices.size():
			radii.append(float(desired_radii))
	elif desired_radii is PackedFloat32Array:
		radii = desired_radii
	else:
		for r in desired_radii:
			radii.append(float(r))
	while radii.size() < vertices.size():
		radii.append(MIN_DRIVE_RADIUS + FILLET_RADIUS_MARGIN)
	var entries := PackedVector2Array()
	var exits := PackedVector2Array()
	for index in vertices.size():
		var previous := vertices[posmod(index - 1, vertices.size())]
		var corner := vertices[index]
		var following := vertices[(index + 1) % vertices.size()]
		var incoming := previous.direction_to(corner)
		var outgoing := corner.direction_to(following)
		var turn := absf(incoming.angle_to(outgoing))
		var half_turn := turn * 0.5
		var desired_radius: float = radii[index]
		desired_radius = maxf(desired_radius, MIN_DRIVE_RADIUS)
		var tangent: float = desired_radius * sin(half_turn) / maxf(cos(half_turn) * cos(half_turn), 0.08)
		tangent = minf(tangent, minf(previous.distance_to(corner), corner.distance_to(following)) * 0.42)
		entries.append(corner - incoming * tangent)
		exits.append(corner + outgoing * tangent)

	var result := PackedVector2Array()
	for index in vertices.size():
		var entry := entries[index]
		var corner := vertices[index]
		var exit := exits[index]
		result.append(entry)
		for step in range(1, 4):
			var t := float(step) / 4.0
			var inverse := 1.0 - t
			result.append(entry * inverse * inverse + corner * 2.0 * inverse * t + exit * t * t)
		result.append(exit)
		var next_entry := entries[(index + 1) % vertices.size()]
		var straight_length := exit.distance_to(next_entry)
		var subdivisions := maxi(1, ceili(straight_length / STRAIGHT_CONTROL_SPACING))
		for step in range(1, subdivisions):
			result.append(exit.lerp(next_entry, float(step) / float(subdivisions)))
	return result


static func _per_corner_fillet_radii(seed: int, attempt: int, vertex_count: int) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	var base := MIN_DRIVE_RADIUS + FILLET_RADIUS_MARGIN
	for v in vertex_count:
		var salt := ROUTE_SALT + 0xD7 + attempt * 37 + v * 19
		var roll := _hash_unit(seed, salt)
		var extra := lerpf(5.0, 25.0, roll)
		var r := base + extra
		radii.append(r)
	return radii


static func _route_index(seed: int, attempt: int, tier: StringName = &"") -> int:
	if tier == &"marathon":
		return posmod(_hash32(seed ^ ROUTE_SALT ^ 0x6A4C1) + attempt, ROUTE_GRAMMAR.MARATHON_NAMES.size())
	return posmod(_hash32(seed ^ ROUTE_SALT) + attempt, ROUTE_GRAMMAR.count())


static func _route_name(seed: int, attempt: int, target_length: float, tier: StringName = &"") -> StringName:
	return StringName(_route_definition(seed, attempt, target_length, tier)["recipe"])


static func _route_program_name(seed: int, attempt: int, target_length: float, tier: StringName = &"") -> StringName:
	return StringName(_route_definition(seed, attempt, target_length, tier)["program"])


static func _route_definition(seed: int, attempt: int, target_length: float = 2500.0 * WORLD_SCALE, tier: StringName = &"") -> Dictionary:
	var length_bias := clampf(inverse_lerp(8500.0, 9600.0, target_length), 0.0, 1.0)
	if tier == &"marathon":
		return ROUTE_GRAMMAR.construct_marathon(_route_index(seed, attempt, tier), _hash32(seed ^ (attempt * RHYTHM_SALT)), length_bias)
	return ROUTE_GRAMMAR.construct(_route_index(seed, attempt), _hash32(seed ^ (attempt * RHYTHM_SALT)), length_bias)


static func _technical_perimeter_template() -> PackedVector2Array:
	# A broad perimeter is safer than concave programs after all twelve bounded
	# grammar attempts fail. Its long opposing edges preserve literal straights.
	return PackedVector2Array([
		Vector2(-0.92, -0.18), Vector2(-0.70, -0.74),
		Vector2(0.56, -0.78), Vector2(0.92, -0.28),
		Vector2(0.90, 0.30), Vector2(0.64, 0.74),
		Vector2(-0.56, 0.78), Vector2(-0.92, 0.28),
	])


static func _smooth_controls(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var result := points.duplicate()
	for _pass in passes:
		var smoothed := PackedVector2Array()
		for index in result.size():
			smoothed.append(
				result[posmod(index - 1, result.size())] * 0.125
				+ result[index] * 0.75
				+ result[(index + 1) % result.size()] * 0.125
			)
		result = smoothed
	return result


static func _el_step_corner(polygon: PackedVector2Array) -> Vector2:
	# The EL L has exactly one reflex (concave) vertex: the inner step corner.
	var winding := 1.0 if _polygon_area(polygon) > 0.0 else -1.0
	for i in polygon.size():
		var previous := polygon[posmod(i - 1, polygon.size())]
		var current := polygon[i]
		var next := polygon[(i + 1) % polygon.size()]
		if (current - previous).cross(next - current) * winding < 0.0:
			return current
	return Vector2.ZERO


static func _el_compact_bounds(room_polygon: PackedVector2Array, seed: int, attempt: int) -> Rect2:
	# Compact EL occupies one safe axis-aligned arm of the L instead of the whole
	# perimeter. The L has two arms: a bottom/wide arm (full width, below the
	# step) and a left/tall arm (full height, left of the step). Prefer the tall
	# arm — it is deep enough for a 4-6k dogleg/U to keep a real infield pocket,
	# whereas the wide arm is too shallow for some programs and collapses them
	# into the oval technical perimeter. Each arm is inset by the corridor
	# clearance and capped to a compact size.
	var bounds := _points_rect(room_polygon)
	var step := _el_step_corner(room_polygon)
	if step == Vector2.ZERO:
		return bounds
	var tall_arm := Rect2(bounds.position.x, bounds.position.y, step.x - bounds.position.x, bounds.size.y)
	var wide_arm := Rect2(bounds.position.x, step.y, bounds.size.x, bounds.end.y - step.y)
	var tall := _el_arm_compact_bounds(tall_arm, seed, attempt, 2000.0, 1400.0)
	if tall.size.x >= 1.0:
		return tall
	return _el_arm_compact_bounds(
		wide_arm, seed, attempt,
		lerpf(1800.0, 2300.0, _hash_unit(seed, ROUTE_SALT + 0xE3 + attempt * 7)),
		lerpf(900.0, 1300.0, _hash_unit(seed, ROUTE_SALT + 0xE5 + attempt * 7))
	)


static func _el_arm_compact_bounds(arm: Rect2, seed: int, attempt: int, cap_w: float, cap_h: float) -> Rect2:
	arm = arm.grow(-CORRIDOR_CLEARANCE)
	if arm.size.x < HALF_WIDTH * 2.0 or arm.size.y < HALF_WIDTH * 2.0:
		return Rect2()
	cap_w = minf(arm.size.x, cap_w)
	cap_h = minf(arm.size.y, cap_h)
	# Deterministic placement inside the arm so different seeds use different
	# bounded candidate positions without leaving the room polygon.
	var slack_x := arm.size.x - cap_w
	var slack_y := arm.size.y - cap_h
	var offset := Vector2(
		(_hash_unit(seed, ROUTE_SALT + 0xE7 + attempt * 7) - 0.5) * slack_x,
		(_hash_unit(seed, ROUTE_SALT + 0xE9 + attempt * 7) - 0.5) * slack_y
	)
	var position := arm.position + (arm.size - Vector2(cap_w, cap_h)) * 0.5 + offset
	return Rect2(position, Vector2(cap_w, cap_h))


static func _el_controls(
	family: StringName,
	seed: int,
	attempt: int,
	source_rect: Rect2,
	target_length: float,
	min_self_distance: float,
	room_scale: float,
	folded: bool = false
) -> PackedVector2Array:
	# Seeded L footprint. The elbow (notch) position is parameterized per seed so
	# the L shape genuinely varies (deep vs shallow notch) under a normalized shape
	# comparison; the long edges keep only a small jitter so the 2-straight gate
	# holds under arc-length-uniform sampling.
	var elbow_x := lerpf(-0.20, 0.26, _hash_unit(seed, ROUTE_SALT + 0xC1 + attempt * 7))
	var elbow_y := lerpf(-0.20, 0.16, _hash_unit(seed, ROUTE_SALT + 0xC3 + attempt * 7))
	var anchors := PackedVector2Array([
		Vector2(-0.84, -0.35), Vector2(-0.84, -0.58), Vector2(-0.74, -0.72),
		Vector2(-0.50, -0.76), Vector2(-0.20, -0.76),
		Vector2(elbow_x - 0.12, -0.70),
		Vector2(elbow_x, -0.55),
		Vector2(elbow_x, -0.30),
		Vector2(elbow_x - 0.02, -0.12),
		Vector2(elbow_x - 0.06, elbow_y),
		Vector2(0.28, 0.16), Vector2(0.48, 0.24),
		Vector2(0.70, 0.28), Vector2(0.84, 0.38), Vector2(0.84, 0.58),
		Vector2(0.72, 0.70), Vector2(0.45, 0.76), Vector2(0.10, 0.76),
		Vector2(-0.30, 0.76), Vector2(-0.65, 0.72), Vector2(-0.82, 0.60),
		Vector2(-0.86, 0.35), Vector2(-0.86, 0.05), Vector2(-0.86, -0.20),
	])
	if folded:
		# Marathon-only comb on the lower arm, built from corner vertices and
		# filleted with the shared corner fitter so every tooth keeps a driveable
		# radius after the uniform length fit. The teeth are wide and deep enough
		# that no >220u-saving chord can stay inside the 103u drive corridor
		# across a tooth, so `_best_complex_bypass` cannot replace it with a chord.
		var fold_elbow_x := lerpf(0.06, 0.22, _hash_unit(seed, ROUTE_SALT + 0xD1 + attempt * 7))
		var fold_step_y := lerpf(0.00, 0.14, _hash_unit(seed, ROUTE_SALT + 0xD3 + attempt * 7))
		var comb_depth := lerpf(0.26, 0.34, _hash_unit(seed, ROUTE_SALT + 0xD5 + attempt * 7))
		var teeth := 3
		var half_slot := 0.10
		var comb_right := 0.44
		var comb_left := -0.42
		var pitch := (comb_right - comb_left) / float(teeth)
		var poly := PackedVector2Array()
		poly.append(Vector2(-0.86, -0.76))
		poly.append(Vector2(fold_elbow_x, -0.76))
		poly.append(Vector2(fold_elbow_x, fold_step_y))
		poly.append(Vector2(0.86, fold_step_y))
		poly.append(Vector2(0.86, 0.76))
		var base_y := 0.76
		for i in teeth:
			var cx := comb_right - pitch * (float(i) + 0.5)
			poly.append(Vector2(cx + half_slot, base_y))
			poly.append(Vector2(cx + half_slot, base_y - comb_depth))
			poly.append(Vector2(cx - half_slot, base_y - comb_depth))
			poly.append(Vector2(cx - half_slot, base_y))
		poly.append(Vector2(-0.86, base_y))
		var mapped_poly := PackedVector2Array()
		for point: Vector2 in poly:
			mapped_poly.append(source_rect.get_center() + point * source_rect.size * 0.5)
		# Cut a few convex corners so the folded L carries a real angle mix too,
		# instead of a pure 90-degree comb.
		mapped_poly = ROUTE_GRAMMAR._compound_chamfer(mapped_poly, seed, 4, false)
		mapped_poly = ROUTE_GRAMMAR._drop_collinear_anchors(mapped_poly)
		if mapped_poly.size() < 4:
			return PackedVector2Array()
		var radii := PackedFloat32Array()
		for _index in mapped_poly.size():
			radii.append(260.0)
		var profiled: Dictionary = ROUTE_GRAMMAR.round_corners_profiled(mapped_poly, radii, -1)
		var folded_controls: PackedVector2Array = profiled["controls"]
		if folded_controls.is_empty():
			return PackedVector2Array()
		return _fit_length_scale(folded_controls, source_rect, target_length, min_self_distance, room_scale, attempt)
	var jittered := PackedVector2Array()
	# Per-seed aspect variation changes the L's proportions (a genuine normalized
	# shape feature), so seeded EL routes are distinct beyond just elbow depth.
	var x_stretch := lerpf(0.88, 1.12, _hash_unit(seed, ROUTE_SALT + 0xC5 + attempt * 7))
	var y_stretch := 2.0 - x_stretch
	for i in anchors.size():
		# The elbow (indices 5..9) is already parameterized; keep its jitter small
		# so the smoothing below does not erase the seeded notch depth.
		var magnitude := 0.02 if i < 5 or i > 9 else 0.04
		var jx := (_hash_unit(seed, ROUTE_SALT + 0xA1 + i * 5 + attempt * 7) - 0.5) * magnitude
		var jy := (_hash_unit(seed, ROUTE_SALT + 0xB3 + i * 5 + attempt * 7) - 0.5) * magnitude
		jittered.append(anchors[i] * Vector2(x_stretch, y_stretch) + Vector2(jx, jy))
	# Round only the concave elbow (indices 5..9) so the road curves around the
	# notch and a straight chord cannot cut it, while the long edges stay literal.
	for _pass in 2:
		var elbow := PackedVector2Array()
		for i in range(5, 10):
			var prev := jittered[(i - 1 + jittered.size()) % jittered.size()]
			var cur := jittered[i]
			var next := jittered[(i + 1) % jittered.size()]
			elbow.append(prev * 0.25 + cur * 0.5 + next * 0.25)
		for k in range(5, 10):
			jittered[k] = elbow[k - 5]
	var mapped := PackedVector2Array()
	for point: Vector2 in jittered:
		mapped.append(source_rect.get_center() + point * source_rect.size * 0.5)
	return _fit_length_scale(mapped, source_rect, target_length, min_self_distance, room_scale, attempt)


## Uniformly scale a control loop about the room center so its sampled length
## meets the requested target without dropping under the branch-clearance floor
## or the per-attempt retry ceiling. Returns an empty loop when the input cannot
## be sampled.
static func _fit_length_scale(
	controls: PackedVector2Array,
	source_rect: Rect2,
	target_length: float,
	min_self_distance: float,
	room_scale: float,
	attempt: int
) -> PackedVector2Array:
	var centerline := _sample_centerline(controls)
	var full_length := _polyline_length(centerline)
	if full_length < 1.0:
		return PackedVector2Array()
	# The L footprint's shortest edge needs ~94% of its standard-room extent to
	# keep two literal straights; scaled rooms (large tiers) can shrink further.
	var minimum_scale := 0.94 / maxf(room_scale, 0.001)
	var full_clearance := _minimum_branch_distance(centerline, min_self_distance)
	if full_clearance < INF:
		minimum_scale = maxf(minimum_scale, minf(1.0, min_self_distance / maxf(full_clearance, 1.0)))
	var retry_ceiling := maxf(minimum_scale, 1.0 - float(mini(attempt, MAX_VARIANTS - 1)) * 0.006)
	var length_scale := clampf(target_length / full_length, minimum_scale, retry_ceiling)
	var center := source_rect.get_center()
	var fitted := PackedVector2Array()
	for point: Vector2 in controls:
		fitted.append(center + (point - center) * length_scale)
	return fitted


static func _el_safe_controls(
	family: StringName,
	seed: int,
	attempt: int,
	source_rect: Rect2,
	target_length: float,
	min_self_distance: float,
	room_scale: float
) -> PackedVector2Array:
	# Legacy fixed L footprint: the rare failure fallback when the seeded EL route
	# cannot honor the room polygon or the length budget. Always reported as
	# `el_safe` / fallback=true, never presented as new seed variation. Raw
	# anchors (no smoothing) keep the long edges literal under arc-length sampling.
	var anchors := PackedVector2Array([
		Vector2(-0.84, -0.35), Vector2(-0.84, -0.58), Vector2(-0.74, -0.72),
		Vector2(-0.50, -0.76), Vector2(-0.20, -0.76), Vector2(0.02, -0.70),
		Vector2(0.12, -0.55), Vector2(0.12, -0.30), Vector2(0.10, -0.12),
		Vector2(0.16, 0.02), Vector2(0.28, 0.16), Vector2(0.48, 0.24),
		Vector2(0.70, 0.28), Vector2(0.84, 0.38), Vector2(0.84, 0.58),
		Vector2(0.72, 0.70), Vector2(0.45, 0.76), Vector2(0.10, 0.76),
		Vector2(-0.30, 0.76), Vector2(-0.65, 0.72), Vector2(-0.82, 0.60),
		Vector2(-0.86, 0.35), Vector2(-0.86, 0.05), Vector2(-0.86, -0.20),
	])
	var mapped := PackedVector2Array()
	for point: Vector2 in anchors:
		mapped.append(source_rect.get_center() + point * source_rect.size * 0.5)
	var full_length := _polyline_length(_sample_centerline(mapped))
	if full_length < 1.0:
		return PackedVector2Array()
	var minimum_scale := 0.94 / maxf(room_scale, 0.001)
	var full_clearance := _minimum_branch_distance(_sample_centerline(mapped), min_self_distance)
	if full_clearance < INF:
		minimum_scale = maxf(minimum_scale, minf(1.0, min_self_distance / maxf(full_clearance, 1.0)))
	var retry_ceiling := maxf(minimum_scale, 1.0 - float(mini(attempt, MAX_VARIANTS - 1)) * 0.006)
	var length_scale := clampf(target_length / full_length, minimum_scale, retry_ceiling)
	var center := source_rect.get_center()
	var offset_roll := _hash_unit(seed, VARIANT_SALT + 0x6E1) * 2.0 - 1.0
	var offset := Vector2(offset_roll * source_rect.size.x * (1.0 - length_scale) * 0.03, 0.0)
	for index in mapped.size():
		mapped[index] = center + (mapped[index] - center) * length_scale + offset
	return mapped


static func _map_to_rect(points: PackedVector2Array, target: Rect2) -> PackedVector2Array:
	var source := _points_rect(points)
	if source.size.x < 0.001 or source.size.y < 0.001:
		return PackedVector2Array()
	var result := PackedVector2Array()
	for point: Vector2 in points:
		var normalized := Vector2(
			(point.x - source.position.x) / source.size.x,
			(point.y - source.position.y) / source.size.y
		)
		result.append(target.position + normalized * target.size)
	return result


static func _validate_controls(
	controls: PackedVector2Array,
	source_rect: Rect2,
	room_polygon: PackedVector2Array,
	room_margin: float,
	min_self_distance: float,
	minimum_length: float,
	width_amplitude: float = 0.0,
	route_seed: int = 0,
	forced_half: float = 0.0
) -> Dictionary:
	if controls.size() < 8:
		return {"valid": false, "reason": "too few controls"}
	var centerline := _sample_centerline(controls)
	if _has_self_intersection(centerline):
		return {"valid": false, "reason": "self intersection"}
	var branch_clearance := _minimum_branch_distance(centerline, min_self_distance)
	if branch_clearance < min_self_distance:
		return {"valid": false, "reason": "self distance %.1f < %.1f" % [branch_clearance, min_self_distance]}
	var corridor_boundaries := _corridor_boundary_loops(centerline)
	if corridor_boundaries.is_empty():
		return {"valid": false, "reason": "corridor offset did not produce valid inner and outer contours"}
	for point: Vector2 in centerline:
		if not source_rect.has_point(point):
			return {"valid": false, "reason": "outside source rect"}
		if not room_polygon.is_empty() and not _inside_with_margin(point, room_polygon, room_margin):
			return {"valid": false, "reason": "outside room margin"}
	var loop_length := _polyline_length(centerline)
	if loop_length < minimum_length:
		return {"valid": false, "reason": "below minimum length"}
	var setup_straight_count := _setup_straight_count(centerline)
	if setup_straight_count < 2:
		return {"valid": false, "reason": "only %d setup straight region(s)" % setup_straight_count}
	var literal_straight_count := _literal_straight_count(centerline)
	if literal_straight_count < 2:
		return {"valid": false, "reason": "only %d literal straight region(s)" % literal_straight_count}
	var bypass := _best_complex_bypass(centerline)
	if bool(bypass.get("found", false)):
		return {
			"valid": false,
			"reason": "driveable chord saves %.0fu over %.0fu" % [float(bypass["saving"]), float(bypass["arc"])],
		}
	if width_amplitude > 0.001 or forced_half > 0.0:
		var ws := compute_width_profile(centerline, route_seed, width_amplitude)
		if forced_half > 0.0:
			for i in ws.size():
				ws[i] = forced_half
		if not _local_turn_radii_ok(centerline, ws):
			return {"valid": false, "reason": "local turn radius < w_local + hull"}
		if not _local_branch_spacing_ok(centerline, ws, 70.0):
			return {"valid": false, "reason": "local branch w_a + w_b + gap violated"}
		if not room_polygon.is_empty() and not _local_corridor_edges_inside_room(centerline, ws, room_polygon):
			return {"valid": false, "reason": "variable-width road edge outside room polygon"}
		var min_local_r := INF
		for i in ws.size():
			min_local_r = minf(min_local_r, ws[i] + VEHICLE_HULL_RADIUS)
		return {"valid": true, "centerline": centerline, "length": loop_length, "minimum_turn_radius": min_local_r, "literal_straight_count": literal_straight_count, "setup_straight_count": setup_straight_count}
	var minimum_turn_radius := _minimum_turn_radius(centerline)
	if minimum_turn_radius < MIN_DRIVE_RADIUS:
		return {"valid": false, "reason": "turn radius %.1f < %.1f" % [minimum_turn_radius, MIN_DRIVE_RADIUS]}
	return {"valid": true, "centerline": centerline, "length": loop_length, "minimum_turn_radius": minimum_turn_radius, "literal_straight_count": literal_straight_count, "setup_straight_count": setup_straight_count}


## Existing gameplay validator seam for v8's authoritative analytic samples.
## The legacy controls path remains untouched and continues to sample through
## `_validate_controls`; this entry point never interprets samples as controls.
static func validate_centerline_samples(
	centerline: PackedVector2Array,
	source_rect: Rect2,
	room_polygon: PackedVector2Array,
	room_margin: float,
	min_self_distance: float,
	minimum_length: float,
	maximum_length: float
) -> Dictionary:
	if centerline.size() < 8:
		return {"valid": false, "reason": "too few samples"}
	if _has_self_intersection(centerline):
		return {"valid": false, "reason": "self intersection"}
	var branch_clearance := _minimum_branch_distance(centerline, min_self_distance)
	if branch_clearance < min_self_distance:
		return {"valid": false, "reason": "self distance %.1f < %.1f" % [branch_clearance, min_self_distance]}
	if _corridor_boundary_loops(centerline).is_empty():
		return {"valid": false, "reason": "corridor offset did not produce valid inner and outer contours"}
	for point: Vector2 in centerline:
		if not source_rect.has_point(point):
			return {"valid": false, "reason": "outside source rect"}
		if not room_polygon.is_empty() and not _inside_with_margin(point, room_polygon, room_margin):
			return {"valid": false, "reason": "outside room margin"}
	var loop_length := _polyline_length(centerline)
	if loop_length < minimum_length or loop_length > maximum_length:
		return {"valid": false, "reason": "outside requested length band"}
	var setup_straight_count := _setup_straight_count(centerline)
	if setup_straight_count < 2:
		return {"valid": false, "reason": "only %d setup straight region(s)" % setup_straight_count}
	var literal_straight_count := _literal_straight_count(centerline)
	if literal_straight_count < 2:
		return {"valid": false, "reason": "only %d literal straight region(s)" % literal_straight_count}
	var bypass := _best_complex_bypass(centerline)
	if bool(bypass.get("found", false)):
		return {"valid": false, "reason": "driveable chord saves %.0fu over %.0fu" % [float(bypass["saving"]), float(bypass["arc"])]}
	var minimum_turn_radius := _minimum_turn_radius(centerline)
	if minimum_turn_radius < MIN_DRIVE_RADIUS:
		return {"valid": false, "reason": "turn radius %.1f < %.1f" % [minimum_turn_radius, MIN_DRIVE_RADIUS]}
	return {"valid": true, "centerline": centerline, "length": loop_length, "minimum_turn_radius": minimum_turn_radius, "literal_straight_count": literal_straight_count, "setup_straight_count": setup_straight_count}


static func _detect_pockets(mapped_vertices: PackedVector2Array) -> Array:
	# Concave runs of the mapped polygon deeper than the threshold are bay
	# pockets the scene builder seals. A run counts only when its chord midpoint
	# lies outside the loop (open floor); waist pinches sit inside the hole and
	# are already blocked by the raised island.
	var pockets: Array = []
	var count := mapped_vertices.size()
	if count < 5:
		return pockets
	var positive_winding := _polygon_area(mapped_vertices) > 0.0
	# Straight samples are neutral, not convex separators. Otherwise resampling
	# a bay splits its two concave corners and makes the whole bay disappear.
	var corners := PackedVector2Array()
	var first_convex := -1
	for index in count:
		var incoming := mapped_vertices[posmod(index - 1, count)].direction_to(mapped_vertices[index])
		var outgoing := mapped_vertices[index].direction_to(mapped_vertices[(index + 1) % count])
		var angle := incoming.angle_to(outgoing)
		if absf(angle) <= 0.001:
			continue
		if first_convex < 0 and (angle > 0.0) == positive_winding:
			first_convex = corners.size()
		corners.append(mapped_vertices[index])
	if corners.size() < 5 or first_convex < 0:
		return pockets
	mapped_vertices = PackedVector2Array()
	for index in corners.size():
		mapped_vertices.append(corners[(first_convex + index) % corners.size()])
	count = mapped_vertices.size()
	var in_run := false
	var run_start := 0
	for i in count + 1:
		var index := i % count
		var prev := mapped_vertices[(index - 1 + count) % count]
		var next := mapped_vertices[(index + 1) % count]
		var turn := prev.direction_to(mapped_vertices[index]).angle_to(mapped_vertices[index].direction_to(next))
		var concave := absf(turn) > 0.001 and (turn > 0.0) != positive_winding
		if concave and not in_run:
			in_run = true
			run_start = index
		elif not concave and in_run:
			in_run = false
			var run_end := (index - 1 + count) % count
			var chord_from := mapped_vertices[(run_start - 1 + count) % count]
			var chord_to := mapped_vertices[(run_end + 1) % count]
			var chord := chord_to - chord_from
			if chord.length_squared() < 1600.0:
				continue
			var max_depth := 0.0
			var deepest_point := chord_from
			var cursor := run_start
			while true:
				var point := mapped_vertices[cursor]
				var depth: float = absf(chord.cross(point - chord_from)) / chord.length()
				if depth > max_depth:
					max_depth = depth
					deepest_point = point
				if cursor == run_end:
					break
				cursor = (cursor + 1) % count
			if max_depth < 130.0:
				continue
			var chord_mid := chord_from.lerp(chord_to, 0.5)
			if Geometry2D.is_point_in_polygon(chord_mid, mapped_vertices):
				continue
			var side := deepest_point - chord_mid
			var along := chord / chord.length()
			side -= along * side.dot(along)
			if side.length_squared() > 1.0:
				side = side.normalized()
			var polygon := PackedVector2Array([chord_from - side * 200.0, chord_from])
			cursor = run_start
			while true:
				polygon.append(mapped_vertices[cursor])
				if cursor == run_end:
					break
				cursor = (cursor + 1) % count
			polygon.append(chord_to)
			polygon.append(chord_to - side * 200.0)
			pockets.append({"from": chord_from, "to": chord_to, "side": side, "depth": max_depth, "deepest": deepest_point, "polygon": polygon})
	return pockets


static func _corridor_boundary_loops(centerline: PackedVector2Array) -> Dictionary:
	var centerline_area := absf(_polygon_area(centerline))
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var inner_area := 0.0
	var outer_area := 0.0
	var contours: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		centerline,
		HALF_WIDTH,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_JOINED
	)
	for contour: PackedVector2Array in contours:
		var resolved: Array[PackedVector2Array] = Geometry2D.intersect_polygons(contour, contour)
		var pieces: Array[PackedVector2Array] = resolved if not resolved.is_empty() else [contour]
		for piece: PackedVector2Array in pieces:
			# The round-join offset densifies the contour with near-collinear
			# points that read as self-intersections on long loops; simplify with
			# the same error-bounded pass the builder uses before rejecting.
			var cleaned := GEOMETRY.simplify_loop(_deduplicate_loop(piece), 0.05)
			if cleaned.size() < 3 or _has_self_intersection(cleaned) or not _boundary_loop_hugs_centerline(cleaned, centerline):
				continue
			var area := absf(_polygon_area(cleaned))
			if area > centerline_area and area > outer_area:
				outer = cleaned
				outer_area = area
			elif area < centerline_area and area > inner_area:
				inner = cleaned
				inner_area = area
	if inner.is_empty() or outer.is_empty():
		return {}
	return {"inner": inner, "outer": outer}


static func _boundary_loop_hugs_centerline(loop: PackedVector2Array, centerline: PackedVector2Array) -> bool:
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		for fraction: float in [0.0, 0.5]:
			var sample := from.lerp(to, fraction)
			var nearest := INF
			for center_index in centerline.size():
				nearest = minf(nearest, _point_segment_distance(sample, centerline[center_index], centerline[(center_index + 1) % centerline.size()]))
			if nearest < HALF_WIDTH * 0.62 or nearest > HALF_WIDTH * 1.42:
				return false
	return true


static func _deduplicate_loop(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		if result.is_empty() or point.distance_squared_to(result[result.size() - 1]) > 0.01:
			result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[result.size() - 1]) <= 0.01:
		result.remove_at(result.size() - 1)
	return result


static func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		total += points[index].cross(points[(index + 1) % points.size()])
	return total * 0.5


static func _setup_straight_count(centerline: PackedVector2Array) -> int:
	var count := centerline.size()
	var straight_starts := PackedByteArray()
	for start in count:
		straight_starts.append(1 if _straight_window_length(centerline, start) >= MIN_SETUP_DISTANCE else 0)
	var straight_start_count := straight_starts.count(1)
	if straight_start_count == 0:
		return 0
	if straight_start_count == count:
		return 1
	var regions := 0
	for index in count:
		if straight_starts[index] == 1 and straight_starts[posmod(index - 1, count)] == 0:
			regions += 1
	return regions


static func _straight_window_length(centerline: PackedVector2Array, start: int) -> float:
	var traveled := 0.0
	var longest := 0.0
	for step in range(1, centerline.size() / 2):
		traveled += centerline[(start + step - 1) % centerline.size()].distance_to(centerline[(start + step) % centerline.size()])
		var chord := centerline[start].distance_to(centerline[(start + step) % centerline.size()])
		if chord / maxf(traveled, 1.0) >= SETUP_STRAIGHTNESS:
			longest = traveled
		elif traveled >= MIN_SETUP_DISTANCE:
			break
	return longest


static func _literal_straight_count(centerline: PackedVector2Array) -> int:
	var count := centerline.size()
	var starts := PackedByteArray()
	for start in count:
		starts.append(1 if _literal_straight_window_length(centerline, start) >= MIN_SETUP_DISTANCE else 0)
	if starts.count(1) == 0:
		return 0
	if starts.count(1) == count:
		return 1
	var regions := 0
	for index in count:
		if starts[index] == 1 and starts[posmod(index - 1, count)] == 0:
			regions += 1
	return regions


static func _literal_straight_window_length(centerline: PackedVector2Array, start: int) -> float:
	var reference := centerline[start].direction_to(centerline[(start + 1) % centerline.size()])
	var traveled := 0.0
	for step in range(1, centerline.size() / 2):
		var from := centerline[(start + step - 1) % centerline.size()]
		var to := centerline[(start + step) % centerline.size()]
		if absf(reference.angle_to(from.direction_to(to))) > LITERAL_STRAIGHT_HEADING_TOLERANCE:
			break
		traveled += from.distance_to(to)
	return traveled


static func _minimum_turn_radius(centerline: PackedVector2Array) -> float:
	var minimum := INF
	var span := 3
	for index in centerline.size():
		var before := centerline[posmod(index - span, centerline.size())]
		var current := centerline[index]
		var after := centerline[(index + span) % centerline.size()]
		var incoming := before.direction_to(current)
		var outgoing := current.direction_to(after)
		if absf(incoming.angle_to(outgoing)) < 0.08:
			continue
		var area_twice := absf((current - before).cross(after - before))
		if area_twice < 0.01:
			continue
		var radius := before.distance_to(current) * current.distance_to(after) * before.distance_to(after) / (2.0 * area_twice)
		minimum = minf(minimum, radius)
	return minimum


static func _best_complex_bypass(centerline: PackedVector2Array) -> Dictionary:
	var best := {"found": false, "saving": 0.0}
	var count := centerline.size()
	var drive_radius := HALF_WIDTH - 22.0
	# Exact centerline segment hash: each chord sample only tests the handful of
	# segments that could lie within the drive radius instead of the whole loop.
	var segment_hash := _centerline_segment_hash(centerline, drive_radius)
	for start in range(0, count, 3):
		var route_arc := 0.0
		for step in range(1, count / 2):
			route_arc += centerline[(start + step - 1) % count].distance_to(centerline[(start + step) % count])
			if route_arc < BYPASS_MIN_ARC or step % 3 != 0:
				continue
			if route_arc > BYPASS_MAX_ARC:
				break
			var finish := (start + step) % count
			var chord := centerline[start].distance_to(centerline[finish])
			var saving := route_arc - chord
			if chord < 1.0 or saving < BYPASS_MIN_SAVING or route_arc / chord < BYPASS_MIN_RATIO:
				continue
			if not _chord_inside_corridor(centerline[start], centerline[finish], centerline, drive_radius, segment_hash):
				continue
			if saving > float(best["saving"]):
				best = {
					"found": true,
					"saving": saving,
					"ratio": route_arc / chord,
					"arc": route_arc,
					"chord": chord,
				}
	return best


## Grid over the centerline segments: each segment is registered in every cell
## its bounding box overlaps, with cell size == drive radius. Any point within
## `cell_size` of a segment therefore finds that segment in one of the 3x3 cells
## around the point, so distance queries over those cells are exact.
static func _centerline_segment_hash(centerline: PackedVector2Array, cell_size: float) -> Dictionary:
	var hash: Dictionary = {}
	var count := centerline.size()
	for index in count:
		var from := centerline[index]
		var to := centerline[(index + 1) % count]
		var min_x := int(floor(minf(from.x, to.x) / cell_size))
		var max_x := int(floor(maxf(from.x, to.x) / cell_size))
		var min_y := int(floor(minf(from.y, to.y) / cell_size))
		var max_y := int(floor(maxf(from.y, to.y) / cell_size))
		for cell_x in range(min_x, max_x + 1):
			for cell_y in range(min_y, max_y + 1):
				var key := Vector2i(cell_x, cell_y)
				var bucket: Array[int] = hash.get(key, [] as Array[int])
				bucket.append(index)
				hash[key] = bucket
	return hash


static func _chord_inside_corridor(
	from: Vector2,
	to: Vector2,
	centerline: PackedVector2Array,
	drive_radius: float,
	segment_hash: Dictionary
) -> bool:
	for sample in range(1, 20):
		var point := from.lerp(to, float(sample) / 20.0)
		if not _point_within_centerline_radius(point, centerline, segment_hash, drive_radius):
			return false
	return true


## Exact equivalent of scanning every centerline segment for a point whose
## minimum distance is at most `cell_size`: the 3x3 window around the point's
## cell covers its whole radius disk, and any segment within the disk is
## registered in the cell holding its closest point.
static func _point_within_centerline_radius(
	point: Vector2,
	centerline: PackedVector2Array,
	segment_hash: Dictionary,
	cell_size: float
) -> bool:
	var cell := Vector2i(int(floor(point.x / cell_size)), int(floor(point.y / cell_size)))
	for offset_x in range(-1, 2):
		for offset_y in range(-1, 2):
			var bucket: Variant = segment_hash.get(cell + Vector2i(offset_x, offset_y))
			if bucket == null:
				continue
			for index: int in bucket:
				if _point_segment_distance(point, centerline[index], centerline[(index + 1) % centerline.size()]) <= cell_size:
					return true
	return false


static func _inside_with_margin(point: Vector2, polygon: PackedVector2Array, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for index in polygon.size():
		var from: Vector2 = polygon[index]
		var to: Vector2 = polygon[(index + 1) % polygon.size()]
		if _point_segment_distance(point, from, to) < margin:
			return false
	return true


static func _point_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


static func _points_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)


static func _sample_centerline(controls: PackedVector2Array) -> PackedVector2Array:
	return CURVE_SAMPLING.sample(controls)


static func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		total += points[index].distance_to(points[(index + 1) % points.size()])
	return total


static func _minimum_branch_distance(centerline: PackedVector2Array, min_distance: float) -> float:
	var count := centerline.size()
	var cumulative := PackedFloat32Array([0.0])
	for index in count:
		cumulative.append(cumulative[index] + centerline[index].distance_to(centerline[(index + 1) % count]))
	var total_length := cumulative[count]
	# Ignore a local run by traveled distance rather than sample count. Tight but
	# legitimate corners can keep nearby samples within a corridor width.
	# Samples within this traveled distance belong to the same corner. Treating
	# a broad 180-degree bend as two branches rejects safe concave silhouettes.
	var local_arc := maxf(850.0, min_distance * 3.0)
	var minimum := INF
	for first in count:
		for second in range(first + 1, count):
			var forward_arc := cumulative[second] - cumulative[first]
			if minf(forward_arc, total_length - forward_arc) < local_arc:
				continue
			minimum = minf(minimum, centerline[first].distance_to(centerline[second]))
	return minimum


static func _has_self_intersection(points: PackedVector2Array) -> bool:
	var count := points.size()
	for first in count:
		var first_next := (first + 1) % count
		for second in range(first + 1, count):
			var second_next := (second + 1) % count
			if first == second or first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


static func _reorder_to_longest_straight(controls: PackedVector2Array) -> PackedVector2Array:
	var count := controls.size()
	var centerline := _sample_centerline(controls)
	if centerline.size() < 8:
		return controls
	# Map each control to its centerline sample by nearest point (monotonic walk)
	# rather than a control-count ratio. Arc-length-uniform samples from the
	# shared sampler are not aligned with control indices, so the ratio mapping
	# mis-locates a control's sample; nearest-sample is correct for both the
	# legacy 260-point stream and the variable-count shared sampler.
	var span := maxi(4, int(round(float(centerline.size()) * 28.0 / 260.0)))
	var sample_count := centerline.size()
	var best_control := 0
	var best_straight := -1.0
	var cursor := 0
	for index in count:
		var point := controls[index]
		var best_dist := point.distance_squared_to(centerline[cursor])
		while true:
			var next_cursor := (cursor + 1) % sample_count
			var dist := point.distance_squared_to(centerline[next_cursor])
			if dist < best_dist:
				cursor = next_cursor
				best_dist = dist
			else:
				break
		var sample_index := cursor
		var ahead := centerline[(sample_index + span) % sample_count]
		var behind := centerline[(sample_index + sample_count - span) % sample_count]
		var chord := behind.distance_to(ahead)
		if chord < 380.0:
			continue
		var path := 0.0
		for offset in range(1, span * 2 + 1):
			var from := (sample_index + sample_count - span + offset - 1) % sample_count
			var to := (sample_index + sample_count - span + offset) % sample_count
			path += centerline[from].distance_to(centerline[to])
		var straightness := chord / maxf(path, 1.0)
		if straightness > best_straight:
			best_straight = straightness
			best_control = index
	var result := PackedVector2Array()
	for index in count:
		result.append(controls[(best_control + index) % count])
	return result


static func _merge_profile_counts(summaries: Array) -> Dictionary:
	var merged := {"circular": 0, "tightening": 0, "opening": 0, "symmetric": 0}
	for summary: Dictionary in summaries:
		for key: String in summary:
			merged[key] = int(merged.get(key, 0)) + int(summary[key])
	return merged


## Try to replace one non-protected straight run with a pose-preserving excursion
## motif. The start straight (control 0) is protected. Candidates are the longest
## interior straight runs; each splice is whole-loop validated and committed only
## if it still clears every gate, otherwise the original loop is retained.
static func _apply_straight_motif(
	controls: PackedVector2Array,
	source_rect: Rect2,
	room_polygon: PackedVector2Array,
	room_margin: float,
	min_self_distance: float,
	minimum_length: float,
	max_length: float,
	current_length: float
) -> Dictionary:
	var runs := _control_straight_runs(controls)
	var candidates: Array = []
	for run: Dictionary in runs:
		if int(run["start"]) == 0:
			continue
		candidates.append(run)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["length"]) > float(b["length"]))
	var rejections: Array = []
	var centroid := _controls_centroid(controls)
	for k in mini(3, candidates.size()):
		var run: Dictionary = candidates[k]
		var start: Vector2 = controls[int(run["start"])]
		var end: Vector2 = controls[int(run["end"])]
		var run_length := start.distance_to(end)
		var tangent := start.direction_to(end)
		# Bulge toward the loop interior so the excursion never extends the
		# track footprint (which would distort a room's aspect ratio).
		var normal := tangent.rotated(PI * 0.5)
		if (centroid - start).dot(normal) < 0.0:
			normal = -normal
		# Try a deeper excursion first (more added length), then shallower ones,
		# so a motif is a real geometry change, not a 4% wiggle, whenever the free
		# floor and the validator permit it.
		var radii := PackedFloat32Array([
			maxf(SECTIONS.MIN_MOTIF_RADIUS, run_length * 0.28),
			maxf(SECTIONS.MIN_MOTIF_RADIUS, run_length * 0.5),
			maxf(SECTIONS.MIN_MOTIF_RADIUS, run_length),
		])
		for radius: float in radii:
			var motif := SECTIONS.straight_motif(start, tangent, run_length, radius, normal)
			if not bool(motif["accepted"]):
				rejections.append(String(motif["reason"]))
				continue
			var points: PackedVector2Array = motif["points"]
			var spliced := PackedVector2Array()
			for index in range(0, int(run["start"]) + 1):
				spliced.append(controls[index])
			for index in range(1, points.size()):
				spliced.append(points[index])
			for index in range(int(run["end"]) + 1, controls.size()):
				spliced.append(controls[index])
			var validation := _validate_controls(spliced, source_rect, room_polygon, room_margin, min_self_distance, minimum_length)
			if not bool(validation["valid"]):
				rejections.append("splice invalid")
				continue
			if float(validation["length"]) > max_length:
				rejections.append("splice exceeds max length")
				continue
			return {"controls": spliced, "motifs": [String(motif["kind"])], "rejections": rejections, "length": float(validation["length"])}
	return {"controls": controls, "motifs": [], "rejections": rejections, "length": current_length}


## Maximal collinear control runs (straight sections) as [{start, end, length,
## heading}]. start/end are control indices; the run spans controls[start..end].
static func _control_straight_runs(controls: PackedVector2Array) -> Array:
	var runs: Array = []
	var count := controls.size()
	if count < 4:
		return runs
	var dirs := PackedVector2Array()
	for i in count:
		dirs.append((controls[(i + 1) % count] - controls[i]).normalized())
	var i := 0
	while i <= count - 2:
		var reference := dirs[i]
		var j := i
		# Segments 0..count-2 only; segment count-1 is the wrap-around back to the
		# protected start control, so it never joins a linear run.
		while j < count - 2 and absf(reference.angle_to(dirs[j + 1])) <= LITERAL_STRAIGHT_HEADING_TOLERANCE:
			j += 1
		if j >= i:
			var length := controls[i].distance_to(controls[j + 1])
			if length >= MIN_SETUP_DISTANCE:
				runs.append({"start": i, "end": j + 1, "length": length, "heading": reference})
		i = j + 1
	return runs


static func _controls_centroid(controls: PackedVector2Array) -> Vector2:
	var centroid := Vector2.ZERO
	for point: Vector2 in controls:
		centroid += point
	return centroid / float(controls.size())


## Per-candidate orientation guard for the elongated rooms: a profile or motif may
## nudge a marginal loop's aspect below the room's orientation gate, so reject
## that candidate rather than silencing decoration for the whole room category.
static func _room_aspect_ok(controls: PackedVector2Array, room_shape: StringName) -> bool:
	if room_shape != &"long" and room_shape != &"tall":
		return true
	var bounds := _points_rect(controls)
	if room_shape == &"long":
		return bounds.size.x > bounds.size.y * 2.5
	return bounds.size.y > bounds.size.x * 1.2


static func _hash32(value: int) -> int:
	# A compact integer avalanche with bounded intermediate products. Masking to
	# 31 bits keeps behavior identical across native and headless builds.
	var mixed := value & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 0x7FFFFFFF


static func _hash_unit(seed: int, salt: int) -> float:
	return float(_hash32(seed ^ salt)) / 2147483647.0


static func compute_width_profile(centerline: PackedVector2Array, seed: int, amplitude: float) -> PackedFloat32Array:
	var n := centerline.size()
	var widths = PackedFloat32Array()
	widths.resize(n)
	if n < 3 or amplitude <= 0.001:
		var w = 125.0
		for i in n:
			widths[i] = w
		return widths

	var path_distances = PackedFloat32Array()
	path_distances.resize(n)
	path_distances[0] = 0.0
	for i in range(1, n):
		path_distances[i] = path_distances[i-1] + centerline[i].distance_to(centerline[i-1])
	var total_length = path_distances[n-1] + centerline[n-1].distance_to(centerline[0])

	var h_seed1 = _hash_unit(seed, 0x1A2B3C)
	var h_seed2 = _hash_unit(seed, 0x4D5E6F)
	
	# Curvature approx based on turning angle over a small arc length
	var curvatures = PackedFloat32Array()
	curvatures.resize(n)
	var span := 3
	for i in n:
		var p0 = centerline[posmod(i - span, n)]
		var p1 = centerline[i]
		var p2 = centerline[(i + span) % n]
		var d1 = p1 - p0
		var d2 = p2 - p1
		var angle = abs(d1.angle_to(d2))
		var arc = p0.distance_to(p1) + p1.distance_to(p2)
		curvatures[i] = angle / max(arc, 1.0)
		
	# Smooth curvature slightly to prevent spikes
	var smooth_curv = PackedFloat32Array()
	smooth_curv.resize(n)
	for i in n:
		smooth_curv[i] = (curvatures[posmod(i-1, n)] + curvatures[i] + curvatures[(i+1)%n]) / 3.0

	for i in n:
		var s = path_distances[i]
		var norm_s = s / total_length
		
		# harmonics
		var h = sin(norm_s * PI * 2.0 * (2.0 + h_seed1 * 4.0)) * 0.5 + 0.5
		h += sin(norm_s * PI * 2.0 * (5.0 + h_seed2 * 6.0)) * 0.25
		
		var curv_factor = smooth_curv[i] * 100.0 # arbitrary scaling to map curvature to [0, 1] roughly
		
		var w = 125.0 + amplitude * (h * 0.5 + curv_factor * 0.5)
		w = clampf(w, 125.0, 240.0)
		widths[i] = w
		
	return widths

static func _local_turn_radii_ok(centerline: PackedVector2Array, ws: PackedFloat32Array) -> bool:
	var span := 3
	for index in centerline.size():
		var before := centerline[posmod(index - span, centerline.size())]
		var current := centerline[index]
		var after := centerline[(index + span) % centerline.size()]
		var incoming := before.direction_to(current)
		var outgoing := current.direction_to(after)
		if absf(incoming.angle_to(outgoing)) < 0.08:
			continue
		var area_twice := absf((current - before).cross(after - before))
		if area_twice < 0.01:
			continue
		var radius := before.distance_to(current) * current.distance_to(after) * before.distance_to(after) / (2.0 * area_twice)
		if radius < ws[index] + VEHICLE_HULL_RADIUS:
			return false
	return true

static func _local_branch_spacing_ok(centerline: PackedVector2Array, ws: PackedFloat32Array, gap: float) -> bool:
	var count := centerline.size()
	var cumulative := PackedFloat32Array([0.0])
	for index in count:
		cumulative.append(cumulative[index] + centerline[index].distance_to(centerline[(index + 1) % count]))
	var total_length := cumulative[count]
	var local_arc := 850.0 # fixed min arc for branch checks
	for first in count:
		for second in range(first + 1, count):
			var forward_arc := cumulative[second] - cumulative[first]
			if minf(forward_arc, total_length - forward_arc) < local_arc:
				continue
			var dist = centerline[first].distance_to(centerline[second])
			if dist < ws[first] + ws[second] + gap:
				return false
	return true

static func _local_corridor_edges_inside_room(centerline: PackedVector2Array, ws: PackedFloat32Array, room_polygon: PackedVector2Array) -> bool:
	var n = centerline.size()
	for i in n:
		var p1 = centerline[i]
		var p2 = centerline[(i+1)%n]
		var d = (p2 - p1).normalized()
		var right = Vector2(-d.y, d.x)
		var w = ws[i]
		if not _inside_with_margin(p1 + right * w, room_polygon, 0.0):
			return false
		if not _inside_with_margin(p1 - right * w, room_polygon, 0.0):
			return false
	return true
