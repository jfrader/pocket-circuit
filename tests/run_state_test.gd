extends SceneTree

const RUN_STATE := preload("res://scripts/progression/run_state.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

const CORPUS_SIZE := 200
const ZERO_MEAN_TOL := 0.000001
const ENVELOPE_TOL := 0.0001
const MEAN_TOL := 0.015  # statistical tolerance over 200 samples per axis

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	# --- Determinism and basic creation
	var seed_a := 424242
	var rs: RunState = RUN_STATE.create(seed_a)
	if not _expect(rs.run_seed == seed_a, "create should retain the run seed"):
		return
	if not _expect(rs.act == null and rs.row == null, "act/row start nullable"):
		return
	if not _expect(rs.car_rolls.is_empty() and rs.car_wear.is_empty(), "starts empty, populated on demand"):
		return

	# --- Roll generation basics (use catalog vehicles for real types)
	var rustbug: Dictionary = CATALOG.get_vehicle("rustbug")
	var pinbolt: Dictionary = CATALOG.get_vehicle("pinbolt")
	var scrapjaw: Dictionary = CATALOG.get_vehicle("scrapjaw")
	var dustmite: Dictionary = CATALOG.get_vehicle("dustmite")
	if not _expect(not rustbug.is_empty() and not pinbolt.is_empty(), "catalog vehicles available"):
		return

	var type_compact: String = String(rustbug["car_art"]["type"])
	var type_coupe: String = String(pinbolt["car_art"]["type"])
	var type_muscle: String = String(scrapjaw["car_art"]["type"])
	var type_buggy: String = String(dustmite["car_art"]["type"])
	if not _expect(type_compact == "compact" and type_coupe == "coupe" and type_muscle == "muscle" and type_buggy == "buggy", "car types from catalog"):
		return

	var tier_starter: String = RUN_STATE.get_tier_for_type(type_compact)
	var tier_side: String = RUN_STATE.get_tier_for_type(type_coupe)
	if not _expect(tier_starter == "starter" and tier_side == "sidegrade", "tier mapping"):
		return
	if not _expect(is_equal_approx(RUN_STATE.get_envelope_for_type(type_compact), 0.09) and is_equal_approx(RUN_STATE.get_envelope_for_type(type_coupe), 0.18), "envelopes per tier"):
		return

	var roll1: Dictionary = rs.get_or_create_car_roll("rustbug", type_compact)
	if not _expect(roll1.keys().size() == 6 and RUN_STATE.AXES.all(func(a: String) -> bool: return roll1.has(a)), "roll has all six axes"):
		return
	if not _expect(is_zero(RUN_STATE.sum_of_axes(roll1), ZERO_MEAN_TOL), "zero-mean sum"):
		return
	var env_st: float = RUN_STATE.get_envelope_for_type(type_compact)
	if not _expect(RUN_STATE.max_abs_deviation(roll1) <= env_st + ENVELOPE_TOL, "within starter envelope"):
		return

	# Reproduce exactly
	var roll1_again: Dictionary = rs.get_or_create_car_roll("rustbug", type_compact)
	if not _expect(roll1 == roll1_again, "get_or_create is stable"):
		return
	var roll1_fresh: Dictionary = RUN_STATE.generate_car_roll(seed_a, tier_starter, type_compact, "rustbug")
	if not _expect(roll1 == roll1_fresh, "generate deterministic for same inputs"):
		return

	# Different vehicle -> different roll (same tier)
	var roll_rust: Dictionary = rs.get_or_create_car_roll("rustbug", type_compact)
	var roll_dust: Dictionary = rs.get_or_create_car_roll("dustmite", type_buggy)
	if not _expect(roll_rust != roll_dust, "different vehicles produce different rolls even same tier"):
		return
	if not _expect(is_zero(RUN_STATE.sum_of_axes(roll_dust), ZERO_MEAN_TOL) and RUN_STATE.max_abs_deviation(roll_dust) <= 0.09 + ENVELOPE_TOL, "buggy also starter zero-mean in envelope"):
		return

	# Sidegrade larger envelope
	var roll_pin: Dictionary = rs.get_or_create_car_roll("pinbolt", type_coupe)
	if not _expect(RUN_STATE.max_abs_deviation(roll_pin) <= 0.18 + ENVELOPE_TOL, "coupe sidegrade envelope"):
		return
	if not _expect(not is_equal_approx(RUN_STATE.max_abs_deviation(roll_pin), RUN_STATE.max_abs_deviation(roll_rust)), "different magnitudes across tiers"):
		return

	# --- Corpus validation over many rolls
	var starters: Array[Dictionary] = []
	var sidegrades: Array[Dictionary] = []
	var axis_sums: Dictionary = {"speed": 0.0, "accel": 0.0, "grip": 0.0, "drift": 0.0, "boost": 0.0, "tough": 0.0}
	var max_seen_starter: float = 0.0
	var max_seen_side: float = 0.0
	for i: int in CORPUS_SIZE:
		var s: int = 100000 + i * 37
		var r_st: Dictionary = RUN_STATE.generate_car_roll(s, "starter", "compact", "corpus_c%d" % i)
		var r_si: Dictionary = RUN_STATE.generate_car_roll(s, "sidegrade", "coupe", "corpus_s%d" % i)
		starters.append(r_st)
		sidegrades.append(r_si)
		for a: String in RUN_STATE.AXES:
			axis_sums[a] += float(r_st.get(a, 0.0))
			axis_sums[a] += float(r_si.get(a, 0.0))
		max_seen_starter = maxf(max_seen_starter, RUN_STATE.max_abs_deviation(r_st))
		max_seen_side = maxf(max_seen_side, RUN_STATE.max_abs_deviation(r_si))

	# Means near zero
	for a: String in RUN_STATE.AXES:
		var mean: float = axis_sums[a] / (CORPUS_SIZE * 2.0)
		if not _expect(absf(mean) < MEAN_TOL, "axis %s mean deviation near zero over corpus (got %s)" % [a, mean]):
			return

	# Envelopes respected, and grow with tier
	if not _expect(max_seen_starter <= 0.09 + ENVELOPE_TOL, "starter max observed <= 0.09"):
		return
	if not _expect(max_seen_side <= 0.18 + ENVELOPE_TOL, "sidegrade max observed <= 0.18"):
		return
	if not _expect(max_seen_side > max_seen_starter, "sidegrade budget larger than starter"):
		return

	# Reproducibility across corpus
	var r0: Dictionary = RUN_STATE.generate_car_roll(424242, "starter", "compact", "repro")
	var r0b: Dictionary = RUN_STATE.generate_car_roll(424242, "starter", "compact", "repro")
	if not _expect(r0 == r0b, "identical seed+type+id reproduces exactly"):
		return

	# --- Wear model
	if not _expect(RUN_STATE.advance_wear("clean", 0.1) == "clean", "minor crash no change"):
		return
	if not _expect(RUN_STATE.advance_wear("clean", 0.4) == "dusty", "medium advances one"):
		return
	if not _expect(RUN_STATE.advance_wear("clean", 0.8) == "rusty", "high advances two"):
		return
	if not _expect(RUN_STATE.advance_wear("dusty", 0.5) == "rusty", "dusty + med -> rusty"):
		return
	if not _expect(RUN_STATE.advance_wear("rusty", 0.9) == "dented", "rusty + high -> dented"):
		return
	if not _expect(RUN_STATE.advance_wear("dented", 0.5) == "dented", "dented caps, monotonic"):
		return
	if not _expect(RUN_STATE.restore_at_bench("dented") == "clean", "bench restores to clean"):
		return
	if not _expect(RUN_STATE.is_worn_out("dented"), "dented is worn out"):
		return
	if not _expect(not RUN_STATE.is_worn_out("rusty"), "rusty not yet worn out"):
		return

	# Wear per car in state
	rs.set_car_wear("rustbug", "rusty")
	if not _expect(rs.get_car_wear("rustbug") == "rusty", "wear stored per car"):
		return
	rs.set_car_wear("rustbug", "dented")
	if not _expect(RUN_STATE.is_worn_out(rs.get_car_wear("rustbug")), "worn out detectable"):
		return

	# --- Serialization round-trip
	var rs2: RunState = RUN_STATE.create(987654)
	rs2.get_or_create_car_roll("rustbug", "compact")
	rs2.get_or_create_car_roll("pinbolt", "coupe")
	rs2.set_car_wear("rustbug", "dusty")
	rs2.set_car_wear("pinbolt", "clean")
	rs2.act = 1
	rs2.row = 3
	var snap: Dictionary = RUN_STATE.serialize(rs2)
	if not _expect(int(snap["schema_version"]) == 1 and int(snap["run_seed"]) == 987654 and snap["act"] == 1 and snap["row"] == 3, "serialize captures identity and position"):
		return
	if not _expect((snap["car_rolls"] as Dictionary).has("rustbug") and (snap["car_wear"] as Dictionary)["rustbug"] == "dusty", "serialize includes rolls and wear"):
		return

	var rs3: RunState = RUN_STATE.deserialize(snap)
	if not _expect(rs3.run_seed == 987654 and rs3.act == 1 and rs3.row == 3, "deserialize restores scalars"):
		return
	var restored_roll: Dictionary = rs3.get_or_create_car_roll("rustbug", "compact")
	if not _expect(restored_roll == rs2.get_or_create_car_roll("rustbug", "compact"), "rolls round-trip exactly"):
		return
	if not _expect(rs3.get_car_wear("rustbug") == "dusty" and rs3.get_car_wear("pinbolt") == "clean", "wear round-trips"):
		return

	# Deserialize tolerates bad wear
	var bad: Dictionary = snap.duplicate(true)
	(bad["car_wear"] as Dictionary)["rustbug"] = "broken"
	var rs_bad: RunState = RUN_STATE.deserialize(bad)
	if not _expect(rs_bad.get_car_wear("rustbug") == "clean", "bad wear falls back safely"):
		return

	# Empty deserialize works
	var empty: RunState = RUN_STATE.deserialize({})
	if not _expect(empty.run_seed == 0 and empty.car_rolls.is_empty(), "empty data yields default run state"):
		return

	print("RUN_STATE_TEST PASS")
	quit(0)

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		print("FAIL: ", message)
		quit(1)
		return false
	return true

func is_zero(v: float, tol: float) -> bool:
	return absf(v) <= tol
