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
	var rival_styles := {}
	for driver_id: String in ["juniper", "milo", "tess", "cass"]:
		var driver := CATALOG.get_driver(driver_id)
		var style: Dictionary = driver.get("ai_style", {})
		if not _expect(style.size() == 6, "%s should define all bounded AI personality dimensions" % driver_id):
			return
		rival_styles[driver_id] = style
	if not _expect(rival_styles["juniper"] != rival_styles["milo"] and rival_styles["milo"] != rival_styles["tess"] and rival_styles["tess"] != rival_styles["cass"], "the four rivals should not share identical driving behavior"):
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
	if not _expect(
			not bool(progress["ending_seen"])
			and CATALOG.is_ending_pending(progress)
			and "flicker" in progress["unlocked_vehicles"],
			"winning the final should unlock Flicker and leave the ending pending acknowledgment"
	):
		return

	# Phase B: 4 new quick-race-only chassis (GURI-734); progression asserts above are untouched
	if not _expect(CATALOG.vehicle_ids().size() == 8, "catalog should list eight vehicles total"):
		return
	var quick_only := ["thimble", "spindle", "anvil", "dustmite"]
	for nid: String in quick_only:
		var v := CATALOG.get_vehicle(nid)
		if not _expect(not v.is_empty() and String(v.get("unlock", "")) == "Quick Race", "%s should exist as Quick Race unlock" % nid):
			return
		var avail := String(v.get("availability", "championship"))
		if not _expect(avail == "quick_race", "%s must carry quick_race availability" % nid):
			return
		if not _expect(nid in CATALOG.quick_race_vehicle_ids() and not nid in CATALOG.championship_vehicle_ids(), "%s must be quick-race only via accessors" % nid):
			return
	if not _expect(not ("thimble" in progress["unlocked_vehicles"] or "spindle" in progress["unlocked_vehicles"] or "anvil" in progress["unlocked_vehicles"] or "dustmite" in progress["unlocked_vehicles"]), "new chassis must never be added by championship act unlocks"):
		return
	# all 8 stats_path resources must validate (no hand-invented out-of-range values)
	for vid: String in CATALOG.vehicle_ids():
		var st := CATALOG.create_vehicle_stats(vid)
		if not _expect(st.is_valid() and st.get_validation_errors().is_empty(), "vehicle %s stats_path must validate cleanly" % vid):
			return

	print("CHAMPIONSHIP_CATALOG_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CHAMPIONSHIP_CATALOG_TEST FAIL: " + message)
	quit(1)
	return false
