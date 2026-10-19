extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
const MAP := preload("res://scripts/progression/run_map.gd")
const STATE := preload("res://scripts/progression/run_state.gd")
const STORE := preload("res://scripts/persistence/save_store.gd")
const SAVE_PATH := "user://tests/run_boundary_validation.json"

var _failed := false

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	_test_valid_runs()
	_test_seeded_errand_roundtrip()
	_test_route_roundtrips()
	_test_invalid_runs()
	_test_haul_validation()
	_test_save_recovery()
	if _failed:
		quit(1)
		return
	print("RUN_BOUNDARY_VALIDATION_TEST PASS")
	quit(0)

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		printerr("RUN_BOUNDARY_VALIDATION_TEST FAIL: " + message)
	return condition

func _test_valid_runs() -> void:
	for seed_value: int in [0, 4242, 777777]:
		for act: int in MAP.ACT_SPECS:
			var session := SESSION.create(seed_value)
			if act > 1:
				session._advance_to_act(act)
			var snapshot := SESSION.serialize(session)
			_expect(SESSION.deserialize(snapshot) != null, "generated native roundtrip seed %d act %d" % [seed_value, act])
			var disk: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
			_expect(SESSION.deserialize(disk) != null, "JSON integral numbers roundtrip seed %d act %d" % [seed_value, act])
			_expect(MAP.deserialize(snapshot["current_map"]) != null, "generated map roundtrip")
	var state := STATE.create(4242)
	_expect(STATE.deserialize(STATE.serialize(state)) != null, "standalone state may have null act and row")
	var racing := SESSION.create(4242)
	racing.start_race(racing.current_node_id, 4)
	_expect(SESSION.deserialize(SESSION.serialize(racing)) != null, "in-flight race survives")
	var early_snapshot := SESSION.serialize(SESSION.create(4242))
	early_snapshot.erase("race_in_flight")
	early_snapshot.erase("pending_offer")
	early_snapshot.erase("node_opponents")
	_expect(SESSION.deserialize(early_snapshot) != null, "optional fields absent in early current-schema saves remain supported")
	var legacy := SESSION.deserialize(early_snapshot)
	_expect(legacy.node_opponents.is_empty(), "old saves load with empty assignments")
	_expect(legacy.opponents_for_node(legacy.current_node_id) == SESSION.create(4242).opponents_for_node(legacy.current_node_id), "old saves fill a deterministic playable field on demand")
	for bad: Variant in [[], false, {"4": {}}, {"1": {"missing": {}}}, {"1": {legacy.current_node_id: {}}}]:
		var malformed := early_snapshot.duplicate(true)
		malformed["node_opponents"] = bad
		_expect(SESSION.deserialize(malformed) == null, "malformed assignment container, node or payload is rejected")
	var normalized := SESSION.serialize(SESSION.create(4242))
	var car_id: String = normalized["current_car_id"]
	var part: Dictionary = RunParts.deal(9, racing.car_stats(racing.current_car_id))[0]
	normalized["parts_held"] = [part, "junk"]
	normalized["installed_parts"] = {car_id: [part, false], "unowned-car": [part]}
	var restored := SESSION.deserialize(normalized)
	_expect(restored != null and restored.parts_held == [part] and restored.fitted_parts(car_id) == [part] and not restored.installed_parts.has("unowned-car"), "optional part entries retain existing drop-invalid normalization")

func _test_seeded_errand_roundtrip() -> void:
	for seed_value: int in [0, 1, 42]:
		var session := SESSION.create(seed_value)
		for node: Dictionary in session.current_map.nodes.values():
			if node["type"] != "errand":
				continue
			session.current_node_id = node["id"]
			session.run_state.row = node["row"]
			session.run_state.set_car_wear(session.current_car_id, "rusty")
			var snapshot: Dictionary = JSON.parse_string(JSON.stringify(SESSION.serialize(session)))
			var restored := SESSION.deserialize(snapshot)
			if not _expect(restored != null, "seeded errand survives JSON save"):
				return
			_expect(restored.errand_tune_steps() == session.errand_tune_steps(), "seeded repair strength survives resume")
			_expect(restored.resolve_errand(SESSION.ErrandChoice.TUNE_UP) == session.resolve_errand(SESSION.ErrandChoice.TUNE_UP), "resumed errand applies the same reward")
			_expect(SESSION.deserialize(SESSION.serialize(restored)) != null, "seeded repair outcome remains valid")
			break

func _test_haul_validation() -> void:
	var session := SESSION.create(33333)
	var base := SESSION.serialize(session)
	var fields := ["boot_cars", "impounded_cars", "pending_chaser", "pending_offer_driver", "pending_offer_points", "tow_count", "nitro_count", "towed_to_bench"]
	for key: String in fields:
		base.erase(key)
	var legacy := SESSION.deserialize(base)
	_expect(legacy != null and not legacy.towed_to_bench, "legacy saves have no reserved tow bench")
	for bad: Variant in [1, "true", null, {}, []]:
		var broken := base.duplicate(true)
		broken["towed_to_bench"] = bad
		_expect(SESSION.deserialize(broken) == null, "tow rescue flag must be boolean")
	_expect(legacy != null and legacy.boot_cars.is_empty() and legacy.impounded_cars.is_empty() and legacy.pending_chaser == null and legacy.tow_count == 0 and legacy.nitro_count == 0, "legacy haul fields normalize cold and empty")
	for key: String in ["tow_count", "nitro_count", "pending_offer_points"]:
		for bad: Variant in [-1, 0.5, true, "1", {}, INF, 0x80000000]:
			var broken := base.duplicate(true)
			broken[key] = bad
			_expect(SESSION.deserialize(broken) == null, "malformed haul number rejected: " + key)
	for key: String in ["boot_cars", "impounded_cars", "pending_offer_driver", "pending_chaser"]:
		for bad: Variant in [false, 1, "junk"]:
			var broken := base.duplicate(true)
			broken[key] = bad
			_expect(SESSION.deserialize(broken) == null, "malformed haul container rejected: " + key)
	var offer := session._win_car(session.current_node_id, SESSION.CAR_ORIGIN_RIVAL, SESSION.STARTER_TYPES)
	var vid: String = offer["id"]
	_expect(session.race_it_now(), "boundary fixture hot choice")
	var hot := SESSION.serialize(session)
	_expect(SESSION.deserialize(hot) != null, "valid haul state loads")
	for bad: Variant in [{"unknown": {}}, {session.current_car_id: "junk"}, {vid: {"id": "fake"}}]:
		var broken := hot.duplicate(true)
		broken["boot_cars"] = bad
		_expect(SESSION.deserialize(broken) == null, "boot must contain owned won cars and roster identities")
	for bad: Variant in [[vid], ["unknown"], [session.owned_cars.keys()[0]], [false]]:
		var broken := hot.duplicate(true)
		broken["impounded_cars"] = bad
		_expect(SESSION.deserialize(broken) == null, "impound rejects boot overlap, missing cars and starter")
	for key: String in ["id", "name", "vehicle_id", "avatar_art", "ai_style", "haul_vehicle_id", "chase_vehicle_id"]:
		var broken := hot.duplicate(true)
		broken["pending_chaser"][key] = "junk"
		_expect(SESSION.deserialize(broken) == null, "malformed chaser field rejected: " + key)
	_expect(SESSION.salvage_won_cars(hot).is_empty(), "recovery never banks boot cars")
	session.impound_haul()
	var captured := SESSION.serialize(session)
	_expect(SESSION.deserialize(captured) != null and SESSION.salvage_won_cars(captured).is_empty(), "impound persists and is excluded from recovery rewards")
	captured["impounded_cars"].append(vid)
	_expect(SESSION.deserialize(captured) == null, "duplicate impound is rejected")

func _test_invalid_runs() -> void:
	var base := SESSION.serialize(SESSION.create(4242))
	for key: String in ["current_node_id", "current_car_id", "run_state", "current_map"]:
		var missing := base.duplicate(true)
		missing.erase(key)
		_expect(SESSION.deserialize(missing) == null, "missing required " + key)
	for value: Variant in ["missing", "", 5, {}, false]:
		var broken := base.duplicate(true)
		broken["current_node_id"] = value
		_expect(SESSION.deserialize(broken) == null, "invalid current node %s" % str(value))
	for value: Variant in [-1, 0.5, true, "6", {}, INF, SESSION._maximum_points() + 1]:
		var broken := base.duplicate(true)
		broken["run_points"] = value
		_expect(SESSION.deserialize(broken) == null, "invalid points %s" % str(value))
	for field: String in ["act", "num_rows", "num_paths", "path_count"]:
		for value: Variant in [-1, 0, 999, 1.5, true, "1", {}]:
			var broken := base.duplicate(true)
			broken["current_map"][field] = value
			_expect(MAP.deserialize(broken["current_map"]) == null, "invalid map %s=%s" % [field, str(value)])
			_expect(SESSION.deserialize(broken) == null, "invalid session map %s=%s" % [field, str(value)])
	for field: String in ["act", "row", "run_seed"]:
		var broken := base.duplicate(true)
		broken["run_state"][field] = 2
		_expect(SESSION.deserialize(broken) == null, "contradictory state " + field)
	for field: String in ["act", "row"]:
		for value: Variant in [-1, 999, 0.5, true, "1", {}]:
			var broken := base.duplicate(true)
			broken["run_state"][field] = value
			_expect(STATE.deserialize(broken["run_state"]) == null, "invalid standalone state " + field)
	for field: String in ["schema_version", "run_seed"]:
		var broken := base.duplicate(true)
		broken[field] = float(base[field]) + 0.5
		_expect(SESSION.deserialize(broken) == null, "fractional session " + field)
	for field: String in ["car_rolls", "car_wear"]:
		var broken := base.duplicate(true)
		broken["run_state"][field] = []
		_expect(STATE.deserialize(broken["run_state"]) == null, "invalid standalone state container " + field)
	for field: String in ["run_state", "current_map", "owned_cars", "installed_parts", "parts_held", "resolved_nodes", "race_in_flight"]:
		var broken := base.duplicate(true)
		broken[field] = "not a container"
		_expect(SESSION.deserialize(broken) == null, "wrong nested type " + field)
	var node_id: String = base["current_node_id"]
	var car_id: String = base["current_car_id"]
	for field: String in ["nodes", "children", "parents"]:
		var broken := base.duplicate(true)
		broken["current_map"][field][node_id] = false
		_expect(SESSION.deserialize(broken) == null, "wrong map entry " + field)
	for field: String in ["row", "col", "type"]:
		var broken := base.duplicate(true)
		broken["current_map"]["nodes"][node_id][field] = false
		_expect(SESSION.deserialize(broken) == null, "wrong node field " + field)
	for field: String in ["row", "col"]:
		var broken := base.duplicate(true)
		broken["current_map"]["nodes"][node_id][field] = 0.5
		_expect(SESSION.deserialize(broken) == null, "fractional node " + field)
	for field: String in ["children", "parents"]:
		var broken := base.duplicate(true)
		broken["current_map"][field][node_id] = ["dangling"]
		_expect(SESSION.deserialize(broken) == null, "dangling " + field)
	var asymmetric := base.duplicate(true)
	asymmetric["current_map"]["parents"].clear()
	_expect(SESSION.deserialize(asymmetric) == null, "nonreciprocal edges")
	var bad_edge := base.duplicate(true)
	bad_edge["current_map"]["children"][node_id] = [node_id]
	_expect(SESSION.deserialize(bad_edge) == null, "backwards or same-row edge")
	var empty_map := base.duplicate(true)
	empty_map["current_map"]["nodes"].clear()
	_expect(SESSION.deserialize(empty_map) == null, "empty map")
	for field: String in ["car_rolls", "car_wear"]:
		var broken := base.duplicate(true)
		broken["run_state"][field][car_id] = []
		_expect(SESSION.deserialize(broken) == null, "wrong state entry " + field)
	var bad_roll := base.duplicate(true)
	bad_roll["run_state"]["car_rolls"][car_id]["speed"] = "fast"
	_expect(SESSION.deserialize(bad_roll) == null, "nonnumeric roll")
	for value: Variant in [true, null, INF, NAN, STATE.TIER_ENVELOPES.values().max() + 1.0]:
		var broken := base.duplicate(true)
		broken["run_state"]["car_rolls"][car_id]["speed"] = value
		_expect(SESSION.deserialize(broken) == null, "invalid roll amount %s" % str(value))
	var bad_parts := base.duplicate(true)
	bad_parts["installed_parts"][car_id] = {}
	_expect(SESSION.deserialize(bad_parts) == null, "fitted parts must be an array before normalization")
	for field: String in ["seed", "act"]:
		var broken := base.duplicate(true)
		broken["owned_cars"][car_id][field] = []
		_expect(SESSION.deserialize(broken) == null, "malformed owned car " + field)
	var malformed_salvage := base.duplicate(true)
	malformed_salvage["owned_cars"][car_id]["won_from"] = SESSION.CAR_ORIGIN_RIVAL
	malformed_salvage["owned_cars"][car_id]["seed"] = []
	_expect(SESSION.salvage_won_cars(malformed_salvage).is_empty(), "salvage rejects malformed numeric car data safely")
	for field: String in ["failed", "completed", "lockup_used", "bench_action_done"]:
		var broken := base.duplicate(true)
		broken[field] = "true"
		_expect(SESSION.deserialize(broken) == null, "wrong boolean " + field)
	var bad_resolved := base.duplicate(true)
	bad_resolved["resolved_nodes"] = {"missing": true}
	_expect(SESSION.deserialize(bad_resolved) == null, "resolved node must belong to map")
	for value: Variant in ["true", 1, [], false]:
		var broken := base.duplicate(true)
		broken["resolved_nodes"][node_id] = value
		_expect(SESSION.deserialize(broken) == null, "resolved marker must be true boolean")
	var bad_flight := base.duplicate(true)
	bad_flight["race_in_flight"] = {"node": "missing", "field": 4}
	_expect(SESSION.deserialize(bad_flight) == null, "in-flight node must be the pending current race")
	for value: Variant in [0, -1, 1.5, true, "4"]:
		var broken := base.duplicate(true)
		broken["race_in_flight"] = {"node": node_id, "field": value}
		_expect(SESSION.deserialize(broken) == null, "invalid in-flight field size")
	var contradictory := base.duplicate(true)
	contradictory["failed"] = true
	contradictory["completed"] = true
	_expect(SESSION.deserialize(contradictory) == null, "cannot be failed and completed")

func _test_save_recovery() -> void:
	var store := STORE.new(SAVE_PATH)
	store.remove_save()
	var session := SESSION.create(4242)
	var won_id := session._add_car("test-win", SESSION.CAR_ORIGIN_RIVAL, SESSION.STARTER_TYPES)
	var data := store.default_data()
	data["difficulty"] = "clockwork"
	data["music_volume"] = 0.25
	data["best_event_finishes"] = {"kitchen_crumb_rush": 1}
	data["current_run"] = SESSION.serialize(session)
	_expect(store.save_data(data), "valid pathed fixture saved")
	var before := store.load_data()
	# Leave a valid but stale backup: recovery must not roll back unrelated primary settings.
	_expect(store.save_data(data), "valid backup staged")
	data["music_volume"] = 0.5
	data["current_run"]["current_node_id"] = "missing"
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var recovered := store.load_data()
	_expect((recovered["current_run"] as Dictionary).is_empty(), "invalid current run is removed before UI")
	_expect(recovered["difficulty"] == "clockwork" and recovered["music_volume"] == 0.5, "primary settings preserved instead of stale backup")
	_expect(recovered["best_event_finishes"] == before["best_event_finishes"], "championship preserved")
	var cars: Array = recovered["garage_cars"]
	_expect(cars.size() == 1 and cars[0]["id"] == won_id, "valid won car salvaged from rejected run")
	_expect(not store.last_load_error.is_empty() and not store.recovery_message.is_empty(), "run recovery is reported")
	_expect(not "backup" in store.recovery_message.to_lower(), "diagnostic does not falsely claim backup recovery")
	_expect(not store.save_data(data), "saving a malformed live run is refused")
	# A recovered primary must not displace the last valid backup on the next save.
	_expect(store.save_data(recovered), "recovered data can be saved")
	file = FileAccess.open(SAVE_PATH + ".bak", FileAccess.READ)
	var backup: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	_expect(SESSION.deserialize(backup["current_run"]) != null, "last valid run backup preserved")
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("broken JSON")
	file.close()
	var from_backup := store.load_data()
	_expect(SESSION.deserialize(from_backup["current_run"]) != null and "backup" in store.recovery_message, "whole-file corruption still recovers validated backup")
	# Historic supported save versions without a run still normalize without recovery.
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 4, "difficulty": "sunday_drive"}))
	file.close()
	var migrated := store.load_data()
	_expect(migrated["version"] == STORE.CURRENT_VERSION and migrated["difficulty"] == "sunday_drive", "historic no-run migration preserved")
	_expect(store.recovery_message.is_empty(), "historic empty run is not corruption")
	# Older run rules still hand over their independently valid won cars.
	data = store.default_data()
	data["current_run"] = SESSION.serialize(session)
	data["current_run"]["schema_version"] = SESSION.SCHEMA_VERSION - 1
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var retired := store.load_data()
	_expect(retired["current_run"].is_empty() and retired["garage_cars"].size() == 1 and retired["garage_cars"][0]["id"] == won_id, "historic incompatible run salvage preserved")
	store.remove_save()

func _test_route_roundtrips() -> void:
	for seed_value: int in [4242, 33333, 98765]:
		var session := SESSION.create(seed_value)
		var steps := 0
		while not session.is_complete() and not session.is_failed() and steps < 100:
			steps += 1
			var kind: String = session.current_node()["type"]
			match kind:
				"race", "act_rival":
					session.resolve_race(session.current_node_id, 1, 4)
				"rival":
					session.resolve_rival(session.current_node_id, true)
				"lockup":
					session.open_lockup()
				"errand":
					session.resolve_errand(0)
				"parts_van":
					var stock := session.van_stock()
					session.buy_part(stock[0]["part"])
				"bench":
					if not session.parts_held.is_empty():
						session.bench_fit(session.current_car_id, 0)
					else:
						session.bench_repair(session.current_car_id)
			var snapshot := SESSION.serialize(session)
			var disk: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
			var restored := SESSION.deserialize(disk)
			if not _expect(restored != null, "played route roundtrip seed %d step %d kind %s" % [seed_value, steps, kind]):
				return
			var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(SESSION.serialize(restored)))
			_expect(roundtrip == disk, "played route loses no state")
			session = restored
			session.decline_offer()
			if not session.is_complete() and not session.is_race_pending():
				var options := session.available_nodes()
				if not _expect(not options.is_empty(), "unfinished route has next stop"):
					return
				_expect(session.enter_node(options[0]["id"]), "route advances")
		_expect(session.is_complete(), "all three acts complete after validated roundtrips")
