extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _expect(CATALOG.CAST.size() == 6, "catalog should contain the six documented cast members"):
		return
	if not _expect(CATALOG.EVENTS.size() == 9 and CATALOG.ACTS.size() == 3, "catalog should contain nine events in three acts"):
		return
	for event: Dictionary in CATALOG.EVENTS:
		if not _expect(String(event.get("theme", "")) in ["kitchen", "workshop", "office"], "every event should declare a supported track theme"):
			return
		if not _expect(event.has("reverse") and event.has("race_format") and event.has("opponent_count"), "every event should declare direction, race format, and opponent count"):
			return
		var expected_opponents := 1 if String(event["race_format"]) == "rival_duel" else 3
		if not _expect(int(event["opponent_count"]) == expected_opponents and (event["opponents"] as Array).size() == expected_opponents, "catalog race size should match its explicit format"):
			return
	if not _expect(bool(CATALOG.get_event("kitchen_mug_run")["reverse"]) and bool(CATALOG.get_event("workshop_ruler_drop")["reverse"]) and bool(CATALOG.get_event("office_keyboard_cut")["reverse"]), "each act's second event should run in reverse"):
		return
	if not _expect(not bool(CATALOG.get_event("office_last_light")["reverse"]) and String(CATALOG.get_event("office_last_light")["race_format"]) == "circuit", "the grand final should remain a four-car forward circuit"):
		return
	if not _expect(CATALOG.get_event("kitchen_clean_line")["opponents"] == ["juniper"] and CATALOG.get_event("workshop_heavy_metal")["opponents"] == ["milo"], "rival duels should name exactly one opponent"):
		return
	if not _expect(CATALOG.get_event("kitchen_crumb_rush")["opponents"].size() == 3 and CATALOG.get_event("office_last_light")["opponents"].size() == 3, "normal events should retain three opponents"):
		return
	if not _expect([CATALOG.score_for_finish(1), CATALOG.score_for_finish(2), CATALOG.score_for_finish(3), CATALOG.score_for_finish(4)] == [10, 7, 5, 3], "finish points should be 10/7/5/3"):
		return

	var progress: Dictionary = SAVE_STORE.new("user://unused_catalog_test.json").default_data()
	if not _expect(not CATALOG.has_progress(progress), "an untouched save should not expose Continue"):
		return
	progress["championship_started"] = true
	if not _expect(CATALOG.has_progress(progress), "a started but unraced championship should expose Continue"):
		return
	if not _expect(CATALOG.is_event_unlocked("kitchen_crumb_rush", progress), "the first event should start unlocked"):
		return
	if not _expect(not CATALOG.is_event_unlocked("kitchen_mug_run", progress), "the second event should start locked"):
		return

	progress = CATALOG.apply_event_result(progress, "kitchen_crumb_rush", 1)["save"]
	if not _expect(CATALOG.is_event_unlocked("kitchen_mug_run", progress), "ten act points should unlock event two"):
		return
	progress = CATALOG.apply_event_result(progress, "kitchen_mug_run", 2)["save"]
	if not _expect(not CATALOG.is_event_unlocked("kitchen_clean_line", progress), "seventeen act points should not unlock the rival"):
		return
	progress = CATALOG.apply_event_result(progress, "kitchen_mug_run", 1)["save"]
	if not _expect(CATALOG.is_event_unlocked("kitchen_clean_line", progress), "twenty act points should unlock the rival"):
		return
	var weaker_retry := CATALOG.apply_event_result(progress, "kitchen_mug_run", 4)
	if not _expect(int(weaker_retry["save"]["best_event_points"]["kitchen_mug_run"]) == 10 and int(weaker_retry["points_gained"]) == 0, "a retry must not reduce a best result"):
		return

	progress = CATALOG.apply_event_result(progress, "kitchen_clean_line", 1)["save"]
	if not _expect("pinbolt" in progress["unlocked_vehicles"] and "kitchen" in progress["completed_acts"], "winning Act I should unlock Pinbolt"):
		return
	if not _expect(CATALOG.is_event_unlocked("workshop_screw_loose", progress), "winning Act I should unlock Act II"):
		return

	for event_id: String in ["workshop_screw_loose", "workshop_ruler_drop", "workshop_heavy_metal"]:
		progress = CATALOG.apply_event_result(progress, event_id, 1)["save"]
	if not _expect("scrapjaw" in progress["unlocked_vehicles"] and "workshop" in progress["completed_acts"], "winning Act II should unlock Scrapjaw"):
		return
	for event_id: String in ["office_paper_trail", "office_keyboard_cut", "office_last_light"]:
		progress = CATALOG.apply_event_result(progress, event_id, 1)["save"]
	if not _expect(progress["ending_seen"] and "flicker" in progress["unlocked_vehicles"], "winning the final should unlock Flicker and the ending"):
		return

	print("CHAMPIONSHIP_CATALOG_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CHAMPIONSHIP_CATALOG_TEST FAIL: " + message)
	quit(1)
	return false
