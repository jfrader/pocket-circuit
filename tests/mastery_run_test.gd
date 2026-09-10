extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const CIRCUITS := preload("res://scripts/progression/championship_circuit_identity.gd")
const MASTERY := preload("res://scripts/progression/mastery_run.gd")


func _initialize() -> void:
	var event := _event_for_seed(661)
	var metrics := MASTERY.prepare_circuit_metrics(event)
	var context := MASTERY.create_context(event, "rustbug", metrics)
	var rustbug: Dictionary = context["identity"]
	var targets: Dictionary = context["targets"]
	var pinbolt := MASTERY.create_identity(event, "pinbolt", metrics)
	if not _expect(not rustbug.is_empty() and not pinbolt.is_empty(), "current generated events and vehicle resources should create mastery identities"):
		return
	if not _expect(MASTERY.identity_key(rustbug) != MASTERY.identity_key(pinbolt), "vehicle configuration must participate in compatibility"):
		return
	var difficulty_variant := event.duplicate(true)
	difficulty_variant["difficulty"] = "clockwork"
	if not _expect(MASTERY.create_context(difficulty_variant, "rustbug", metrics) == context, "difficulty must not influence mastery identity or targets"):
		return

	var reverse_event := event.duplicate(true)
	reverse_event["reverse"] = not bool(event.get("reverse", false))
	var reverse_metrics := MASTERY.prepare_circuit_metrics(reverse_event)
	var reverse_context := MASTERY.create_context(reverse_event, "rustbug", reverse_metrics)
	var regenerated := rustbug.duplicate(true)
	regenerated["circuit"]["generator_version"] = int(regenerated["circuit"]["generator_version"]) + 1
	if not _expect(MASTERY.identity_key(rustbug) != MASTERY.identity_key(reverse_context["identity"]) and MASTERY.identity_key(rustbug) != MASTERY.identity_key(regenerated), "direction and generator version must prevent incompatible comparisons"):
		return

	if not _expect(float(targets["gold"]) < float(targets["silver"]) and float(targets["silver"]) < float(targets["bronze"]), "medal targets should expose calibrated increasing thresholds"):
		return
	if not _expect(targets == MASTERY.targets_for_event(event, metrics) and metrics == MASTERY.prepare_circuit_metrics(event) and int(targets["version"]) == MASTERY.TARGET_CALIBRATION_VERSION, "prepared metrics and targets should repeat deterministically with explicit versions"):
		return
	var longer_event := _event_for_seed(662)
	var longer_metrics := MASTERY.prepare_circuit_metrics(longer_event)
	var longer_targets := MASTERY.targets_for_event(longer_event, longer_metrics)
	for seed in range(663, 680):
		if absf(float(longer_targets["racing_line_length"]) - float(targets["racing_line_length"])) > 100.0:
			break
		longer_event = _event_for_seed(seed)
		longer_metrics = MASTERY.prepare_circuit_metrics(longer_event)
		longer_targets = MASTERY.targets_for_event(longer_event, longer_metrics)
	var length_delta := float(longer_targets["racing_line_length"]) - float(targets["racing_line_length"])
	var gold_delta := float(longer_targets["gold"]) - float(targets["gold"])
	var length_ratio := float(longer_targets["racing_line_length"]) / float(targets["racing_line_length"])
	var target_ratio := float(longer_targets["gold"]) / float(targets["gold"])
	if not _expect(absf(length_delta) > 100.0 and signf(length_delta) == signf(gold_delta) and absf(length_ratio - target_ratio) < 0.01, "longer realized generated racing lines should produce proportionally slower targets"):
		return
	var extra_laps := event.duplicate(true)
	extra_laps["laps"] = int(event["laps"]) * 2
	var extra_lap_targets := MASTERY.targets_for_event(extra_laps, metrics)
	if not _expect(absf(float(extra_lap_targets["gold"]) - float(targets["gold"]) * 2.0) <= 0.11, "target time should scale proportionally with lap count"):
		return
	var straight_metrics := metrics.duplicate(true)
	straight_metrics["turn_demand"] = 1.0
	straight_metrics["technical_fraction"] = 0.05
	var technical_metrics := metrics.duplicate(true)
	technical_metrics["turn_demand"] = 2.5
	technical_metrics["technical_fraction"] = 0.45
	var straight_targets := MASTERY.calibrate_targets(straight_metrics, int(event["laps"]))
	var technical_targets := MASTERY.calibrate_targets(technical_metrics, int(event["laps"]))
	if not _expect(float(technical_targets["gold"]) > float(straight_targets["gold"]) and float(technical_targets["technical_pace_multiplier"]) > float(straight_targets["technical_pace_multiplier"]), "equal-length technical lines should receive a deterministic turn-demand pace adjustment"):
		return

	var best_lap := float(targets["gold"]) / float(targets["lap_count"]) * 0.95
	var first := MASTERY.apply_result([], rustbug, targets, best_lap, float(targets["silver"]) - 0.1)
	if not _expect(String(first["record"]["medal"]) == "silver" and first["record"]["targets"] == targets and first["new_best_lap"] and first["new_best_race"] and first["medal_improved"], "the first compatible run should preserve targets and record lap, race, and earned medal"):
		return
	var slower := MASTERY.apply_result(first["records"], rustbug, targets, best_lap + 1.0, float(targets["bronze"]) + 8.0)
	if not _expect(is_equal_approx(float(slower["record"]["best_lap"]), best_lap) and is_equal_approx(float(slower["record"]["best_race"]), float(targets["silver"]) - 0.1), "slower runs must not replace compatible personal bests"):
		return

	var historical_identity := rustbug.duplicate(true)
	historical_identity["calibration"]["version"] = int(historical_identity["calibration"]["version"]) + 1
	historical_identity["calibration"]["fingerprint"] = "historical-calibration"
	var historical_targets := targets.duplicate(true)
	historical_targets["version"] = historical_identity["calibration"]["version"]
	historical_targets["fingerprint"] = historical_identity["calibration"]["fingerprint"]
	historical_targets["gold"] = float(targets["gold"]) * 0.7
	historical_targets["silver"] = float(targets["gold"]) * 0.8
	historical_targets["bronze"] = float(targets["gold"]) * 0.9
	var historical_race := float(historical_targets["silver"]) - 0.1
	var historical := MASTERY.apply_result(slower["records"], historical_identity, historical_targets, historical_race * 0.45, historical_race)
	if not _expect(historical["records"].size() == 2, "a new calibration version should retain the incompatible historical record"):
		return
	var historical_record := MASTERY.compatible_record(historical["records"], historical_identity)
	if not _expect(String(historical_record["medal"]) == "silver" and historical_record["targets"] == MASTERY.normalize_targets(historical_targets, historical_identity) and MASTERY.compatible_record(historical["records"], rustbug) == slower["record"], "historical medals should continue using their stored calibration metadata without comparing as current"):
		return
	if not _expect(MASTERY.car_configuration("rustbug") == MASTERY.car_configuration("rustbug") and String(MASTERY.car_configuration("rustbug")["fingerprint"]).length() == 20, "car configuration fingerprints should be stable and explicit"):
		return
	print("MASTERY_RUN_TEST PASS")
	quit(0)


func _event_for_seed(seed: int) -> Dictionary:
	return CIRCUITS.apply_to_event(
		CATALOG.get_event("kitchen_crumb_rush"),
		CIRCUITS.event_identity(CIRCUITS.create_championship(seed), "kitchen_crumb_rush")
	)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MASTERY_RUN_TEST FAIL: " + message)
	quit(1)
	return false