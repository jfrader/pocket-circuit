extends SceneTree

const ROSTER := preload("res://scripts/progression/driver_roster.gd")
const AI_CONTROLLER := preload("res://scripts/vehicle/ai_vehicle_controller.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var vehicles4: Array = ["rustbug", "pinbolt", "scrapjaw", "flicker"]
	var vehicles8: Array = vehicles4 + ["thimble", "spindle", "anvil", "dustmite"]

	# PLAYER_ID stable and separate
	if not _expect(ROSTER.PLAYER_ID == "player", "PLAYER_ID must be stable constant"):
		return
	var r0 := ROSTER.create(123, vehicles4, 3)
	if not _expect(not r0.is_empty(), "basic create must succeed"):
		return
	for op: Dictionary in r0["opponents"]:
		if not _expect(String(op["id"]) != ROSTER.PLAYER_ID, "roster must not contain player id"):
			return

	# multiple seeds produce different rosters
	var rA := ROSTER.create(1001, vehicles4, 3)
	var rB := ROSTER.create(1002, vehicles4, 3)
	if not _expect(rA != rB and int(rA["seed"]) != int(rB["seed"]), "different seeds must produce different rosters"):
		return

	# repeated generation is identical (deterministic)
	var r1 := ROSTER.create(424242, vehicles4, 3)
	var r2 := ROSTER.create(424242, vehicles4, 3)
	if not _expect(r1 == r2, "same seed+vehicles+count must be identical"):
		return
	if not _expect(String(r1["fingerprint"]) == String(r2["fingerprint"]), "fingerprints must match on repeat"):
		return

	# unique identities within a roster
	var ids := {}
	var names := {}
	var av_seeds := {}
	for op: Dictionary in r1["opponents"]:
		var oid := String(op["id"])
		var onm := String(op["name"])
		var avs := int((op.get("avatar_art", {}) as Dictionary).get("seed", -1))
		if not _expect(not ids.has(oid), "ids must be unique in roster"):
			return
		if not _expect(not names.has(onm), "names must be unique in roster"):
			return
		if not _expect(not av_seeds.has(avs), "avatar seeds must be independent/unique in roster"):
			return
		ids[oid] = true
		names[onm] = true
		av_seeds[avs] = true
	if not _expect(ids.size() == 3 and names.size() == 3, "exactly 3 unique driver identities"):
		return

	# The profiles are the roster's own vocabulary, but they must stay inside the
	# bounds the AI controller applies, or a generated driver would be clamped.
	for personality_name: String in ROSTER.PERSONALITIES:
		var profile: Dictionary = ROSTER.PERSONALITIES[personality_name]
		for trait_key: String in profile:
			var limits: Vector2 = AI_CONTROLLER.PERSONALITY_BOUNDS[trait_key]
			var value := float(profile[trait_key])
			# Vector2 stores 32-bit components while the profile holds 64-bit
			# floats, so the declared bounds must be compared with a tolerance.
			var epsilon := 0.0001
			if not _expect(value >= limits.x - epsilon and value <= limits.y + epsilon, "%s.%s (%.2f) must stay inside the AI controller's %.2f-%.2f bounds" % [personality_name, trait_key, value, limits.x, limits.y]):
				return

	# every field mixes routing personalities: a short-cut taker and a patient
	# driver are always present, so no roster is three identical strangers
	for probe_seed in [5, 77, 4242, 900001]:
		var field := ROSTER.create(probe_seed, vehicles8, 3)
		if not _expect(not field.is_empty(), "field probe seed %d should generate" % probe_seed):
			return
		var takers := 0
		for op: Dictionary in field["opponents"]:
			if float(op["ai_style"]["shortcut_preference"]) >= 1.10:
				takers += 1
		if not _expect(takers >= 1 and takers < 3, "seed %d should field both a short-cut taker and a patient driver, not %d takers of 3" % [probe_seed, takers]):
			return

	# car variety (without replacement where possible)
	var used_v := {}
	for op: Dictionary in r1["opponents"]:
		used_v[op["vehicle_id"]] = true
	if not _expect(used_v.size() == 3, "should assign distinct cars when pool allows"):
		return

	# JSON roundtrip deterministic + normalize preserves
	var text := JSON.stringify(r1)
	var parsed: Variant = JSON.parse_string(text)
	var norm := ROSTER.normalize(parsed, vehicles4, 3)
	if not _expect(norm == r1, "JSON roundtrip + normalize must be identical to original"):
		return

	# stable after catalog growth (additions, no regen)
	var r_small := ROSTER.create(98765, vehicles4, 3)
	var norm_grown := ROSTER.normalize(r_small, vehicles8, 3)
	if not _expect(not norm_grown.is_empty(), "normalize with grown catalog must accept old roster"):
		return
	if not _expect(norm_grown == r_small, "grown catalog must not alter existing assignments or identity"):
		return
	# confirm same vehicle assignments survived
	for i in 3:
		if not _expect(String(r_small["opponents"][i]["vehicle_id"]) == String(norm_grown["opponents"][i]["vehicle_id"]), "vehicle assignments stable after growth"):
			return

	# normalization rejects invalid
	if not _expect(ROSTER.normalize(null, vehicles4, 3).is_empty(), "null raw -> empty"):
		return
	if not _expect(ROSTER.normalize({}, vehicles4, 3).is_empty(), "empty dict -> empty"):
		return
	var bad_ver := r1.duplicate(true)
	bad_ver["schema_version"] = 99
	if not _expect(ROSTER.normalize(bad_ver, vehicles4, 3).is_empty(), "bad schema -> empty"):
		return
	var bad_count := r1.duplicate(true)
	bad_count["count"] = 9
	if not _expect(ROSTER.normalize(bad_count, vehicles4, 3).is_empty(), "count mismatch -> empty"):
		return
	var bad_seed := r1.duplicate(true)
	bad_seed["seed"] = -5
	if not _expect(ROSTER.normalize(bad_seed, vehicles4, 3).is_empty(), "bad seed -> empty"):
		return
	var bad_veh := r1.duplicate(true)
	bad_veh["opponents"][0]["vehicle_id"] = "not-in-catalog"
	if not _expect(ROSTER.normalize(bad_veh, vehicles4, 3).is_empty(), "out-of-catalog vehicle -> empty"):
		return
	var dup_id := r1.duplicate(true)
	dup_id["opponents"][1]["id"] = dup_id["opponents"][0]["id"]
	if not _expect(ROSTER.normalize(dup_id, vehicles4, 3).is_empty(), "duplicate id -> empty"):
		return
	var dup_name := r1.duplicate(true)
	dup_name["opponents"][2]["name"] = dup_name["opponents"][0]["name"]
	if not _expect(ROSTER.normalize(dup_name, vehicles4, 3).is_empty(), "duplicate name -> empty"):
		return
	var bad_fp := r1.duplicate(true)
	bad_fp["fingerprint"] = "deadbeefdeadbeef"
	if not _expect(ROSTER.normalize(bad_fp, vehicles4, 3).is_empty(), "mismatched fingerprint -> empty"):
		return
	var bad_ai := r1.duplicate(true)
	bad_ai["opponents"][0]["ai_style"]["corner_pace"] = 9.9
	if not _expect(ROSTER.normalize(bad_ai, vehicles4, 3).is_empty(), "an invented ai_style must be rejected, not clamped"):
		return
	var bad_art := r1.duplicate(true)
	bad_art["opponents"][0]["avatar_art"]["seed"] = -1
	if not _expect(ROSTER.normalize(bad_art, vehicles4, 3).is_empty(), "bad avatar seed -> empty"):
		return

	# slot selection
	var full := ROSTER.create(777, vehicles4, 3)
	var slot1 := ROSTER.opponents_for_slots(full, [2])
	var slot2 := ROSTER.opponents_for_slots(full, [1, 0])
	if not _expect(slot1.size() == 1 and String(slot1[0]["id"]) == String(full["opponents"][2]["id"]), "duels select their tournament rival's slot"):
		return
	if not _expect(slot2.size() == 2 and slot2[1] == full["opponents"][0], "slot ordering follows the event without regenerating identities"):
		return
	if not _expect(ROSTER.opponents_for_slots(full, [99]).is_empty(), "out-of-range slots reject the selection"):
		return
	if not _expect(ROSTER.opponents_for_slots({}, [0]).is_empty() and ROSTER.opponents_for_slots(full, [0, 0]).is_empty(), "empty or repeated slot selection is invalid"):
		return

	# create rejects bad inputs
	if not _expect(ROSTER.create(1, [], 3).is_empty(), "empty vehicles -> empty"):
		return
	if not _expect(ROSTER.create(1, vehicles4, 0).is_empty(), "zero count -> empty"):
		return
	if not _expect(ROSTER.create(-1, vehicles4, 2).is_empty(), "negative seed -> empty"):
		return
	var dups_v := vehicles4.duplicate()
	dups_v.append("rustbug")
	if not _expect(ROSTER.create(5, dups_v, 2).is_empty(), "dup vehicles in list -> empty"):
		return
	for invalid: Variant in [null, 7, [], "wrong"]:
		var malformed := r1.duplicate(true)
		malformed["opponents"][0] = invalid
		if not _expect(ROSTER.normalize(malformed, vehicles4, 3).is_empty(), "malformed profile must be rejected without a script error"):
			return
	for invalid: Variant in [NAN, INF, 1.5, "1", {}, []]:
		var malformed := r1.duplicate(true)
		malformed["seed"] = invalid
		if not _expect(ROSTER.normalize(malformed, vehicles4, 3).is_empty(), "invalid seed type or value must be rejected without coercion"):
			return
	var bad_options := r1.duplicate(true)
	bad_options["opponents"][0]["avatar_art"]["options"] = "wrong"
	if not _expect(ROSTER.normalize(bad_options, vehicles4, 3).is_empty(), "avatar options must match the stored generated-profile contract"):
		return
	var nan_ai := r1.duplicate(true)
	nan_ai["opponents"][0]["ai_style"]["corner_pace"] = NAN
	if not _expect(ROSTER.normalize(nan_ai, vehicles4, 3).is_empty(), "non-finite AI values must not enter physics"):
		return
	for seed_value in 50:
		var sample := ROSTER.create(seed_value, vehicles8, ROSTER.MAX_OPPONENTS)
		if not _expect(not sample.is_empty() and ROSTER.normalize(JSON.parse_string(JSON.stringify(sample)), vehicles8, ROSTER.MAX_OPPONENTS) == sample, "generated rosters must survive save/load across many seeds"):
			return

	print("DRIVER_ROSTER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("DRIVER_ROSTER_TEST FAIL: " + message)
	quit(1)
	return false
