class_name MasteryRun
extends RefCounted

const RECORD_VERSION := 1
const CAR_CONFIGURATION_VERSION := 1
const CIRCUIT_METRICS_VERSION := 1
const TARGET_CALIBRATION_VERSION := 1
const TARGET_FORMULA_ID := "racing-line-reference-pace"
const MAX_RECORDED_TIME := 3600.0
const REFERENCE_TOP_SPEED := 692.0
const GOLD_SPEED_PERMILLE := 820
const TURN_EXCESS_PENALTY_PERMILLE := 90
const TECHNICAL_FRACTION_PENALTY_PERMILLE := 180
const MAX_TECHNICAL_PENALTY_PERMILLE := 350
const SILVER_TIME_PERMILLE := 1130
const BRONZE_TIME_PERMILLE := 1280
const TARGET_TIME_STEP := 0.1
const CATALOG := preload("res://data/championship/catalog.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")

static func create_context(event: Dictionary, vehicle_id: String, metrics_value: Variant) -> Dictionary:
	var targets := targets_for_event(event, metrics_value)
	var identity := _create_identity(event, vehicle_id, targets)
	return {"identity": identity, "targets": targets} if not identity.is_empty() else {"identity": {}, "targets": targets}


static func create_identity(event: Dictionary, vehicle_id: String, metrics_value: Variant) -> Dictionary:
	return create_context(event, vehicle_id, metrics_value)["identity"]


static func _create_identity(event: Dictionary, vehicle_id: String, targets: Dictionary) -> Dictionary:
	var circuit_fingerprint := String(event.get("circuit_fingerprint", ""))
	if circuit_fingerprint.is_empty() or targets.is_empty():
		return {}
	var car := car_configuration(vehicle_id)
	if car.is_empty():
		return {}
	return {
		"event_id": String(event.get("id", "")),
		"circuit": {
			"schema_version": int(event.get("circuit_schema_version", 0)),
			"generator_version": int(event.get("circuit_generator_version", 0)),
			"fingerprint": circuit_fingerprint,
			"direction": "reverse" if bool(event.get("reverse", false)) else "forward",
		},
		"calibration": {
			"version": int(targets["version"]),
			"fingerprint": String(targets["fingerprint"]),
		},
		"car": car,
	}


static func car_configuration(vehicle_id: String) -> Dictionary:
	var vehicle := CATALOG.get_vehicle(vehicle_id)
	if vehicle.is_empty():
		return {}
	var stats := ResourceLoader.load(String(vehicle.get("stats_path", ""))) as VehicleStats
	if stats == null:
		return {}
	var property_names: Array[String] = []
	for property_name: String in VehicleStats.PARAMETER_RANGES:
		property_names.append(property_name)
	property_names.sort()
	var parts := PackedStringArray([
		"pc-car-configuration-v%d" % CAR_CONFIGURATION_VERSION,
		vehicle_id,
		"physics_model_version=%d" % stats.physics_model_version,
	])
	for property_name: String in property_names:
		parts.append("%s=%s" % [property_name, _canonical_float(float(stats.get(property_name)))])
	return {
		"schema_version": CAR_CONFIGURATION_VERSION,
		"vehicle_id": vehicle_id,
		"physics_model_version": stats.physics_model_version,
		"fingerprint": "|".join(parts).sha256_text().substr(0, 20),
	}


static func identity_key(identity: Dictionary) -> String:
	var normalized := normalize_identity(identity)
	if normalized.is_empty():
		return ""
	var circuit: Dictionary = normalized["circuit"]
	var calibration: Dictionary = normalized["calibration"]
	var car: Dictionary = normalized["car"]
	return ("pc-mastery-record-v%d|%s|circuit=%d:%d:%s:%s|calibration=%d:%s|car=%d:%s:%d:%s" % [
		RECORD_VERSION,
		String(normalized["event_id"]),
		int(circuit["schema_version"]),
		int(circuit["generator_version"]),
		String(circuit["fingerprint"]),
		String(circuit["direction"]),
		int(calibration["version"]),
		String(calibration["fingerprint"]),
		int(car["schema_version"]),
		String(car["vehicle_id"]),
		int(car["physics_model_version"]),
		String(car["fingerprint"]),
	]).sha256_text()


static func normalize_identity(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	var event_id := String(raw.get("event_id", ""))
	var circuit_value: Variant = raw.get("circuit")
	var calibration_value: Variant = raw.get("calibration")
	var car_value: Variant = raw.get("car")
	if event_id.is_empty() or event_id.length() > 128 or circuit_value is not Dictionary or calibration_value is not Dictionary or car_value is not Dictionary:
		return {}
	var circuit := circuit_value as Dictionary
	var calibration := calibration_value as Dictionary
	var car := car_value as Dictionary
	var direction := String(circuit.get("direction", ""))
	var circuit_fingerprint := String(circuit.get("fingerprint", ""))
	var calibration_fingerprint := String(calibration.get("fingerprint", ""))
	var vehicle_id := String(car.get("vehicle_id", ""))
	var car_fingerprint := String(car.get("fingerprint", ""))
	if direction not in ["forward", "reverse"]:
		return {}
	if circuit_fingerprint.is_empty() or circuit_fingerprint.length() > 128 or calibration_fingerprint.is_empty() or calibration_fingerprint.length() > 128 or vehicle_id.is_empty() or vehicle_id.length() > 128 or car_fingerprint.is_empty() or car_fingerprint.length() > 128:
		return {}
	for version: Variant in [circuit.get("schema_version"), circuit.get("generator_version"), calibration.get("version"), car.get("schema_version")]:
		if not _is_positive_integer(version):
			return {}
	if not _is_nonnegative_integer(car.get("physics_model_version")):
		return {}
	return {
		"event_id": event_id,
		"circuit": {
			"schema_version": int(circuit["schema_version"]),
			"generator_version": int(circuit["generator_version"]),
			"fingerprint": circuit_fingerprint,
			"direction": direction,
		},
		"calibration": {
			"version": int(calibration["version"]),
			"fingerprint": calibration_fingerprint,
		},
		"car": {
			"schema_version": int(car["schema_version"]),
			"vehicle_id": vehicle_id,
			"physics_model_version": int(car["physics_model_version"]),
			"fingerprint": car_fingerprint,
		},
	}


static func circuit_metrics_key_for_event(event: Dictionary) -> String:
	return _circuit_metrics_key(_event_circuit(event))


## Worker-only fallback for migrated saves. Runtime races should publish the
## metrics already attached to their prepared route instead of calling this.
static func prepare_circuit_metrics(event: Dictionary) -> Dictionary:
	var identity_value: Variant = event.get("circuit_identity")
	if identity_value is not Dictionary:
		return {}
	var identity := identity_value as Dictionary
	var sub_seeds: Dictionary = identity.get("sub_seeds", {}) if identity.get("sub_seeds") is Dictionary else {}
	if not sub_seeds.has("route"):
		return {}
	var prepared := TRACK_BUILDER.prepare_layout(
		StringName(identity.get("theme", event.get("theme", "kitchen"))),
		StringName(identity.get("room", event.get("room", "classic"))),
		int(sub_seeds["route"]),
		{
			"act": int(event.get("act", 1)),
			"obstacles_enabled": false,
			"sub_seeds": sub_seeds.duplicate(true),
		}
	)
	return circuit_metrics_from_prepared(event, prepared.get("racing_line_metrics", {}))


static func circuit_metrics_from_prepared(event: Dictionary, metrics_value: Variant) -> Dictionary:
	if metrics_value is not Dictionary:
		return {}
	var identity_value: Variant = event.get("circuit_identity")
	if identity_value is not Dictionary:
		return {}
	var identity := identity_value as Dictionary
	var sub_seeds: Dictionary = identity.get("sub_seeds", {}) if identity.get("sub_seeds") is Dictionary else {}
	if not sub_seeds.has("route"):
		return {}
	var metrics := metrics_value as Dictionary
	return normalize_circuit_metrics({
		"version": CIRCUIT_METRICS_VERSION,
		"circuit": _event_circuit(event),
		"route_seed": int(sub_seeds["route"]),
		"sample_count": metrics.get("sample_count"),
		"racing_line_length": metrics.get("racing_line_length"),
		"absolute_turn_radians": metrics.get("absolute_turn_radians"),
		"turn_demand": metrics.get("turn_demand"),
		"technical_fraction": metrics.get("technical_fraction"),
		"max_sample_turn_radians": metrics.get("max_sample_turn_radians"),
	}, event)


static func normalize_circuit_metrics(value: Variant, event: Dictionary = {}) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	var circuit_value: Variant = raw.get("circuit")
	if int(raw.get("version", 0)) != CIRCUIT_METRICS_VERSION or circuit_value is not Dictionary or not _is_nonnegative_integer(raw.get("route_seed")) or not _is_positive_integer(raw.get("sample_count")):
		return {}
	var circuit := circuit_value as Dictionary
	var normalized_circuit := _normalize_circuit(circuit)
	var racing_line_length := snappedf(_valid_number(raw.get("racing_line_length"), 1.0, 1000000.0), 0.001)
	var absolute_turn_radians := snappedf(_valid_metric_number(raw.get("absolute_turn_radians"), 10000.0), 0.000001)
	var turn_demand := snappedf(_valid_metric_number(raw.get("turn_demand"), 1000.0), 0.000001)
	var technical_fraction := snappedf(_valid_metric_number(raw.get("technical_fraction"), 1.0), 0.000001)
	var max_sample_turn := snappedf(_valid_metric_number(raw.get("max_sample_turn_radians"), PI), 0.000001)
	if normalized_circuit.is_empty() or racing_line_length <= 0.0 or absolute_turn_radians < 0.0 or turn_demand < 0.0 or technical_fraction < 0.0 or max_sample_turn < 0.0:
		return {}
	var normalized := {
		"version": int(raw["version"]),
		"circuit": normalized_circuit,
		"route_seed": int(raw["route_seed"]),
		"sample_count": int(raw["sample_count"]),
		"racing_line_length": racing_line_length,
		"absolute_turn_radians": absolute_turn_radians,
		"turn_demand": turn_demand,
		"technical_fraction": technical_fraction,
		"max_sample_turn_radians": max_sample_turn,
	}
	if not event.is_empty():
		var expected_key := circuit_metrics_key_for_event(event)
		var identity: Dictionary = event.get("circuit_identity", {})
		var sub_seeds: Dictionary = identity.get("sub_seeds", {}) if identity.get("sub_seeds") is Dictionary else {}
		if expected_key.is_empty() or _circuit_metrics_key(normalized_circuit) != expected_key or int(normalized["route_seed"]) != int(sub_seeds.get("route", -1)):
			return {}
	return normalized


static func normalize_circuit_metrics_map(value: Variant) -> Dictionary:
	var output := {}
	if value is not Dictionary:
		return output
	for item: Variant in (value as Dictionary).values():
		var metrics := normalize_circuit_metrics(item)
		if metrics.is_empty():
			continue
		output[_circuit_metrics_key(metrics["circuit"])] = metrics
	return output


static func metrics_for_event(metrics_map_value: Variant, event: Dictionary) -> Dictionary:
	if metrics_map_value is not Dictionary:
		return {}
	var key := circuit_metrics_key_for_event(event)
	if key.is_empty():
		return {}
	return normalize_circuit_metrics((metrics_map_value as Dictionary).get(key), event)


static func targets_for_event(event: Dictionary, metrics_value: Variant) -> Dictionary:
	var metrics := normalize_circuit_metrics(metrics_value, event)
	return calibrate_targets(metrics, maxi(1, int(event.get("laps", 1))))


static func calibrate_targets(metrics: Dictionary, lap_count: int) -> Dictionary:
	if metrics.is_empty() or lap_count <= 0:
		return {}
	var circuit: Dictionary = metrics["circuit"]
	# Calibration v1 starts gold at 82% of the 692 u/s chassis ceiling, near a
	# strong Club AI reference, then adds bounded penalties for cumulative turn
	# demand and dense technical samples. Silver and bronze add 13% and 28%.
	var turn_excess := maxf(float(metrics["turn_demand"]) - 1.0, 0.0)
	var technical_penalty := minf(
		turn_excess * float(TURN_EXCESS_PENALTY_PERMILLE) / 1000.0
		+ float(metrics["technical_fraction"]) * float(TECHNICAL_FRACTION_PENALTY_PERMILLE) / 1000.0,
		float(MAX_TECHNICAL_PENALTY_PERMILLE) / 1000.0
	)
	var pace_multiplier := 1.0 + technical_penalty
	var gold := float(metrics["racing_line_length"]) * float(lap_count) * pace_multiplier / (REFERENCE_TOP_SPEED * float(GOLD_SPEED_PERMILLE) / 1000.0)
	var targets := {
		"version": TARGET_CALIBRATION_VERSION,
		"formula_id": TARGET_FORMULA_ID,
		"metrics_version": int(metrics["version"]),
		"route_seed": int(metrics["route_seed"]),
		"racing_line_length": float(metrics["racing_line_length"]),
		"absolute_turn_radians": float(metrics["absolute_turn_radians"]),
		"turn_demand": float(metrics["turn_demand"]),
		"technical_fraction": float(metrics["technical_fraction"]),
		"technical_pace_multiplier": snappedf(pace_multiplier, 0.000001),
		"lap_count": lap_count,
		"reference_top_speed": REFERENCE_TOP_SPEED,
		"gold_speed_per_mille": GOLD_SPEED_PERMILLE,
		"turn_excess_penalty_per_mille": TURN_EXCESS_PENALTY_PERMILLE,
		"technical_fraction_penalty_per_mille": TECHNICAL_FRACTION_PENALTY_PERMILLE,
		"max_technical_penalty_per_mille": MAX_TECHNICAL_PENALTY_PERMILLE,
		"silver_time_per_mille": SILVER_TIME_PERMILLE,
		"bronze_time_per_mille": BRONZE_TIME_PERMILLE,
		"gold": snappedf(gold, TARGET_TIME_STEP),
		"silver": snappedf(gold * float(SILVER_TIME_PERMILLE) / 1000.0, TARGET_TIME_STEP),
		"bronze": snappedf(gold * float(BRONZE_TIME_PERMILLE) / 1000.0, TARGET_TIME_STEP),
	}
	targets["fingerprint"] = _target_fingerprint(targets, circuit)
	return normalize_targets(targets)


static func normalize_targets(value: Variant, identity: Dictionary = {}) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	var fingerprint := String(raw.get("fingerprint", ""))
	var formula_id := String(raw.get("formula_id", ""))
	var integer_fields := ["version", "metrics_version", "route_seed", "lap_count", "gold_speed_per_mille", "turn_excess_penalty_per_mille", "technical_fraction_penalty_per_mille", "max_technical_penalty_per_mille", "silver_time_per_mille", "bronze_time_per_mille"]
	for field: String in integer_fields:
		if not _is_nonnegative_integer(raw.get(field)) or (field in ["version", "metrics_version", "lap_count", "gold_speed_per_mille", "silver_time_per_mille", "bronze_time_per_mille"] and int(raw.get(field, 0)) <= 0):
			return {}
	if fingerprint.is_empty() or fingerprint.length() > 128 or formula_id.is_empty() or formula_id.length() > 128:
		return {}
	var racing_line_length := snappedf(_valid_number(raw.get("racing_line_length"), 1.0, 1000000.0), 0.001)
	var absolute_turn_radians := snappedf(_valid_metric_number(raw.get("absolute_turn_radians"), 10000.0), 0.000001)
	var turn_demand := snappedf(_valid_metric_number(raw.get("turn_demand"), 1000.0), 0.000001)
	var technical_fraction := snappedf(_valid_metric_number(raw.get("technical_fraction"), 1.0), 0.000001)
	var pace_multiplier := snappedf(_valid_number(raw.get("technical_pace_multiplier"), 0.0, 10.0), 0.000001)
	var reference_top_speed := snappedf(_valid_number(raw.get("reference_top_speed"), 1.0, 10000.0), 0.001)
	var gold := snappedf(_valid_time(raw.get("gold")), 0.001)
	var silver := snappedf(_valid_time(raw.get("silver")), 0.001)
	var bronze := snappedf(_valid_time(raw.get("bronze")), 0.001)
	if racing_line_length <= 0.0 or absolute_turn_radians < 0.0 or turn_demand < 0.0 or technical_fraction < 0.0 or pace_multiplier < 1.0 or reference_top_speed <= 0.0 or gold <= 0.0 or not gold < silver or not silver < bronze:
		return {}
	if not identity.is_empty():
		var normalized_identity := normalize_identity(identity)
		if normalized_identity.is_empty():
			return {}
		var calibration: Dictionary = normalized_identity["calibration"]
		if int(calibration["version"]) != int(raw["version"]) or String(calibration["fingerprint"]) != fingerprint:
			return {}
	return {
		"version": int(raw["version"]),
		"formula_id": formula_id,
		"fingerprint": fingerprint,
		"metrics_version": int(raw["metrics_version"]),
		"route_seed": int(raw["route_seed"]),
		"racing_line_length": racing_line_length,
		"absolute_turn_radians": absolute_turn_radians,
		"turn_demand": turn_demand,
		"technical_fraction": technical_fraction,
		"technical_pace_multiplier": pace_multiplier,
		"lap_count": int(raw["lap_count"]),
		"reference_top_speed": reference_top_speed,
		"gold_speed_per_mille": int(raw["gold_speed_per_mille"]),
		"turn_excess_penalty_per_mille": int(raw["turn_excess_penalty_per_mille"]),
		"technical_fraction_penalty_per_mille": int(raw["technical_fraction_penalty_per_mille"]),
		"max_technical_penalty_per_mille": int(raw["max_technical_penalty_per_mille"]),
		"silver_time_per_mille": int(raw["silver_time_per_mille"]),
		"bronze_time_per_mille": int(raw["bronze_time_per_mille"]),
		"gold": gold,
		"silver": silver,
		"bronze": bronze,
	}


static func normalize_records(value: Variant) -> Array:
	var output: Array = []
	if value is not Array:
		return output
	var keys := {}
	for item: Variant in value:
		var record := normalize_record(item)
		if record.is_empty():
			continue
		var key := identity_key(record["identity"])
		if keys.has(key):
			var index := int(keys[key])
			output[index] = _merge_records(output[index], record)
		else:
			keys[key] = output.size()
			output.append(record)
	return output


static func normalize_record(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	if int(raw.get("version", 0)) != RECORD_VERSION:
		return {}
	var identity := normalize_identity(raw.get("identity"))
	var targets := normalize_targets(raw.get("targets"), identity)
	var best_lap := _valid_time(raw.get("best_lap"))
	var best_race := _valid_time(raw.get("best_race"))
	if identity.is_empty() or targets.is_empty() or best_lap <= 0.0 or best_race <= 0.0 or best_lap > best_race:
		return {}
	return {
		"version": RECORD_VERSION,
		"identity": identity,
		"targets": targets,
		"best_lap": best_lap,
		"best_race": best_race,
		"medal": medal_for(targets, best_race),
	}


static func apply_result(records_value: Variant, identity: Dictionary, targets_value: Variant, best_lap: float, race_time: float) -> Dictionary:
	var records := normalize_records(records_value)
	var normalized_identity := normalize_identity(identity)
	var targets := normalize_targets(targets_value, normalized_identity)
	var valid_lap := _valid_time(best_lap)
	var valid_race := _valid_time(race_time)
	if normalized_identity.is_empty() or targets.is_empty() or valid_lap <= 0.0 or valid_race <= 0.0 or valid_lap > valid_race:
		return {"records": records, "record": {}, "new_best_lap": false, "new_best_race": false, "medal_improved": false}
	var key := identity_key(normalized_identity)
	var existing_index := -1
	for index in records.size():
		if identity_key(records[index]["identity"]) == key:
			existing_index = index
			break
	var previous: Dictionary = records[existing_index] if existing_index >= 0 else {}
	var previous_lap := float(previous.get("best_lap", INF))
	var previous_race := float(previous.get("best_race", INF))
	var previous_medal := String(previous.get("medal", "none"))
	var record := {
		"version": RECORD_VERSION,
		"identity": normalized_identity,
		"targets": targets,
		"best_lap": minf(previous_lap, valid_lap),
		"best_race": minf(previous_race, valid_race),
	}
	record["medal"] = medal_for(targets, float(record["best_race"]))
	if existing_index >= 0:
		record["targets"] = previous["targets"].duplicate(true)
		record["medal"] = medal_for(record["targets"], float(record["best_race"]))
		records[existing_index] = record
	else:
		records.append(record)
	return {
		"records": records,
		"record": record.duplicate(true),
		"new_best_lap": valid_lap < previous_lap,
		"new_best_race": valid_race < previous_race,
		"medal_improved": medal_rank(String(record["medal"])) > medal_rank(previous_medal),
	}


static func compatible_record(records_value: Variant, identity: Dictionary) -> Dictionary:
	var key := identity_key(identity)
	if key.is_empty():
		return {}
	for record: Dictionary in normalize_records(records_value):
		if identity_key(record["identity"]) == key:
			return record.duplicate(true)
	return {}


static func state(records_value: Variant, identity: Dictionary, targets: Dictionary) -> Dictionary:
	return {
		"identity": normalize_identity(identity),
		"record": compatible_record(records_value, identity),
		"targets": normalize_targets(targets, identity),
	}


static func medal_for(targets_value: Variant, race_time: float) -> String:
	var targets := normalize_targets(targets_value)
	if targets.is_empty() or race_time <= 0.0:
		return "none"
	if race_time <= float(targets["gold"]):
		return "gold"
	if race_time <= float(targets["silver"]):
		return "silver"
	if race_time <= float(targets["bronze"]):
		return "bronze"
	return "none"


static func medal_rank(medal: String) -> int:
	return ["none", "bronze", "silver", "gold"].find(medal)


static func _merge_records(a: Dictionary, b: Dictionary) -> Dictionary:
	var merged := a.duplicate(true)
	merged["best_lap"] = minf(float(a["best_lap"]), float(b["best_lap"]))
	merged["best_race"] = minf(float(a["best_race"]), float(b["best_race"]))
	merged["medal"] = medal_for(merged["targets"], float(merged["best_race"]))
	return merged


static func _target_fingerprint(targets: Dictionary, circuit: Dictionary) -> String:
	return ("pc-mastery-target-v%d|%s|metrics=%d|circuit=%d:%d:%s:%s|route_seed=%d|laps=%d|top_speed=%d|gold_speed=%d|turn_penalty=%d|technical_penalty=%d|max_penalty=%d|silver=%d|bronze=%d" % [
		int(targets["version"]),
		String(targets["formula_id"]),
		int(targets["metrics_version"]),
		int(circuit.get("schema_version", 0)),
		int(circuit.get("generator_version", 0)),
		String(circuit.get("fingerprint", "")),
		String(circuit.get("direction", "forward")),
		int(targets["route_seed"]),
		int(targets["lap_count"]),
		int(round(float(targets["reference_top_speed"]))),
		int(targets["gold_speed_per_mille"]),
		int(targets["turn_excess_penalty_per_mille"]),
		int(targets["technical_fraction_penalty_per_mille"]),
		int(targets["max_technical_penalty_per_mille"]),
		int(targets["silver_time_per_mille"]),
		int(targets["bronze_time_per_mille"]),
	]).sha256_text().substr(0, 20)


static func _event_circuit(event: Dictionary) -> Dictionary:
	return _normalize_circuit({
		"schema_version": event.get("circuit_schema_version"),
		"generator_version": event.get("circuit_generator_version"),
		"fingerprint": event.get("circuit_fingerprint"),
		"direction": "reverse" if bool(event.get("reverse", false)) else "forward",
	})


static func _normalize_circuit(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var circuit := value as Dictionary
	var fingerprint := String(circuit.get("fingerprint", ""))
	var direction := String(circuit.get("direction", ""))
	if not _is_positive_integer(circuit.get("schema_version")) or not _is_positive_integer(circuit.get("generator_version")) or fingerprint.is_empty() or fingerprint.length() > 128 or direction not in ["forward", "reverse"]:
		return {}
	return {
		"schema_version": int(circuit["schema_version"]),
		"generator_version": int(circuit["generator_version"]),
		"fingerprint": fingerprint,
		"direction": direction,
	}


static func _circuit_metrics_key(circuit: Dictionary) -> String:
	var normalized := _normalize_circuit(circuit)
	if normalized.is_empty():
		return ""
	return ("pc-mastery-circuit-metrics-v%d|%d:%d:%s:%s" % [
		CIRCUIT_METRICS_VERSION,
		int(normalized["schema_version"]),
		int(normalized["generator_version"]),
		String(normalized["fingerprint"]),
		String(normalized["direction"]),
	]).sha256_text()


static func _valid_time(value: Variant) -> float:
	return _valid_number(value, 0.0, MAX_RECORDED_TIME)


static func _valid_number(value: Variant, minimum: float, maximum: float) -> float:
	if value is not int and value is not float:
		return 0.0
	var number := float(value)
	return number if not is_nan(number) and not is_inf(number) and number > minimum and number <= maximum else 0.0


static func _valid_metric_number(value: Variant, maximum: float) -> float:
	if value is not int and value is not float:
		return -1.0
	var number := float(value)
	return number if not is_nan(number) and not is_inf(number) and number >= 0.0 and number <= maximum else -1.0


static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is not int and value is not float:
		return false
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return false
	var integer := int(value)
	return integer >= 0 and float(integer) == number


static func _is_positive_integer(value: Variant) -> bool:
	return _is_nonnegative_integer(value) and int(value) > 0


static func _canonical_float(value: float) -> String:
	return "%.6f" % value