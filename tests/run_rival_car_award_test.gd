extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
var _failed := false

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var sess := SESSION.create(33333)
	_move_to(sess, "rival")
	var driver: Dictionary = sess.opponents_for_node(sess.current_node_id)["opponents"][0]
	var vehicle := CATALOG.get_vehicle(driver["vehicle_id"])
	var outcome := sess.resolve_rival(sess.current_node_id, true)
	_expect(outcome.get("car", {}).get("id") == driver["vehicle_id"], "duel awards the opponent's vehicle")
	_check_award(sess, driver, vehicle)
	var boss := SESSION.create(33333)
	_move_to(boss, "act_rival")
	driver = boss.opponents_for_node(boss.current_node_id)["opponents"][0]
	vehicle = CATALOG.get_vehicle(driver["vehicle_id"])
	outcome = boss.resolve_race(boss.current_node_id, 1, 4)
	_expect(outcome.get("car", {}).get("id") == driver["vehicle_id"] and boss.current_map.act == 2, "act rival awards its actual vehicle before advancing")
	_check_award(boss, driver, vehicle)
	var lockup := SESSION.create(33333)
	_move_to(lockup, "lockup")
	var fresh := lockup.open_lockup()
	_expect(fresh.get("id", "").begins_with("car-") and CATALOG.get_vehicle(fresh["id"]).is_empty(), "lockup still generates a fresh car")
	_expect(lockup.pending_offer_driver.is_empty() and lockup.run_state.get_car_wear(fresh["id"]) == "clean", "lockup car is clean with no robbed driver")
	_expect(sess.send_it_ahead(), "duplicate fixture drives the won car")
	var existing_id := sess.current_car_id
	var existing_car := sess.won_car(existing_id)
	var existing_vehicle := CATALOG.get_vehicle(existing_id)
	sess.run_state.set_car_wear(existing_id, "dusty")
	sess.resolved_nodes.erase(sess.current_node_id)
	outcome = sess.resolve_rival(sess.current_node_id, true)
	_expect(outcome.get("car", {}).get("id") == existing_id, "already owned opponent is still awarded")
	_expect(sess.won_car(existing_id) == existing_car and sess.run_state.get_car_wear(existing_id) == "dusty", "already owned shipped car retains authored identity, empty roll and wear")
	_check_stats(sess, existing_id, existing_vehicle)
	_expect(not sess.boot_cars.has(existing_id) and not sess.impounded_cars.has(existing_id), "duplicate award has one consistent pending custody")
	var loaded := SESSION.deserialize(JSON.parse_string(JSON.stringify(SESSION.serialize(sess))))
	_expect(loaded != null and loaded.pending_offer == existing_id and loaded.pending_offer_driver == sess.pending_offer_driver, "already driven rival award survives persistence")
	if loaded != null:
		_expect(loaded.won_car(existing_id) == existing_car and loaded.run_state.get_car_wear(existing_id) == "dusty", "persistence keeps existing shipped rival identity, empty roll and wear")
		_check_stats(loaded, existing_id, existing_vehicle)
	var final_boss := SESSION.create(33333)
	final_boss._advance_to_act(3)
	_move_to(final_boss, "act_rival")
	driver = final_boss.opponents_for_node(final_boss.current_node_id)["opponents"][0]
	outcome = final_boss.resolve_race(final_boss.current_node_id, 1, 4)
	_expect(final_boss.completed and outcome.get("car", {}).get("id") == driver["vehicle_id"], "final rival awards its car")
	_expect(final_boss.pending_offer.is_empty() and final_boss.collection_safe_cars().size() == 1, "final rival prize banks with the completed night")
	loaded = SESSION.deserialize(JSON.parse_string(JSON.stringify(SESSION.serialize(final_boss))))
	_expect(loaded != null and loaded.completed and loaded.collection_safe_cars() == final_boss.collection_safe_cars(), "completed rival prize survives persistence")
	if _failed:
		quit(1)
		return
	print("RUN_RIVAL_CAR_AWARD_TEST PASS")
	quit(0)

func _check_award(sess: RunSession, driver: Dictionary, vehicle: Dictionary) -> void:
	var vid: String = driver["vehicle_id"]
	_expect(sess.pending_offer == vid and sess.pending_offer_driver == driver, "offer pairs the awarded car with its driver")
	var car := sess.won_car(vid)
	_expect(car.get("seed") == vehicle["car_art"]["seed"] and car.get("type") == vehicle["car_art"]["type"], "award retains vehicle identity")
	_expect(CATALOG.is_shipped(vid) and not vehicle.has("roll") and car.get("roll") == {} and sess.run_state.car_rolls.get(vid) == {}, "shipped opponent and award retain authored stats without generating a roll")
	_check_stats(sess, vid, vehicle)
	var restored := SESSION.deserialize(JSON.parse_string(JSON.stringify(SESSION.serialize(sess))))
	_expect(restored != null, "award survives persistence")
	if restored != null:
		_expect(restored.pending_offer == vid and restored.pending_offer_driver == driver and restored.won_car(vid) == car, "persistence retains car and driver")
		_check_stats(restored, vid, vehicle)

func _check_stats(sess: RunSession, vid: String, vehicle: Dictionary) -> void:
	var expected := CATALOG.build_vehicle_stats(vehicle)
	var actual := sess.car_stats(vid)
	for property: Dictionary in expected.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_expect(actual.get(property["name"]) == expected.get(property["name"]), "award drives like rival: " + property["name"])

func _move_to(sess: RunSession, kind: String) -> void:
	for node: Dictionary in sess.current_map.nodes.values():
		if node["type"] == kind:
			sess.current_node_id = node["id"]
			sess.run_state.row = node["row"]
			return
	_expect(false, "fixture stop exists: " + kind)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_RIVAL_CAR_AWARD_TEST FAIL: " + message)
