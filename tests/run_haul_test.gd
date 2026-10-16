extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
var _failed := false

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var hot := _offer()
	var vid := hot.pending_offer
	_expect(hot.can_race_hot(vid), "assigned run roster supplies a same-band spare")
	var points := hot.run_points
	_expect(hot.race_it_now() and hot.current_car_id == vid, "hot choice switches cars")
	_expect(hot.run_points == points and hot.boot_cars.has(vid) and hot.pending_chaser != null, "hot choice costs nothing and carries driver")
	_expect(not hot.race_it_now(), "offer resolves once")
	var restored := SESSION.deserialize(JSON.parse_string(JSON.stringify(SESSION.serialize(hot))))
	_expect(restored != null and restored.boot_cars == hot.boot_cars and restored.pending_chaser == hot.pending_chaser, "hot identity roundtrips through JSON")
	_expect(hot.impound_haul() == [vid] and hot.boot_cars.is_empty() and hot.pending_chaser == null, "capture moves all boot cars into impound")
	_expect(hot.owned_cars.has(vid) and hot.collection_safe_cars().is_empty(), "impound never deletes a car or banks it")
	_move_to(hot, "parts_van")
	hot.run_points = SESSION.HAUL_RANSOM_POINTS - 1
	_expect(not hot.ransom_car(vid), "ransom requires full payment")
	hot.run_points += 1
	_expect(hot.ransom_car(vid) and hot.run_points == 0 and hot.impounded_cars.is_empty(), "van ransom pays once and returns car to collection")
	_expect(hot.collection_safe_cars().size() == 1 and not hot.ransom_car(vid), "ransomed car is safe, no duplicate ransom")
	var ahead := _offer()
	vid = ahead.pending_offer
	points = ahead.run_points
	var payout := ahead.pending_offer_points
	_expect(payout == SESSION.RUN_POINTS_BY_FINISH[1], "rival win credits its payout")
	_expect(ahead.send_it_ahead() and ahead.run_points == points - payout and ahead.current_car_id == vid, "ahead switches and debits exactly the credited payout")
	_expect(ahead.pending_chaser == null and ahead.boot_cars.has(vid), "ahead carries haul without chase")
	_move_to(ahead, "bench")
	_expect(ahead.bench_bank_haul() and ahead.boot_cars.is_empty() and ahead.bench_action_done, "bench banks using its action")
	_expect(not ahead.bench_repair(vid) and not ahead.bench_bank_haul(), "bank consumes the bench action")
	ahead.failed = true
	_expect(ahead.collection_safe_cars().size() == 1, "banked car survives later night failure")
	var home := _offer()
	var starter := home.current_car_id
	points = home.run_points
	_expect(home.send_it_home() and home.current_car_id == starter and home.run_points == points, "home retains current car and points")
	_expect(home.boot_cars.is_empty() and home.collection_safe_cars().size() == 1, "home is collection safe immediately")
	var boss := _offer()
	_expect(boss.send_it_ahead(), "boss fixture carries haul")
	_move_to(boss, "act_rival")
	boss.resolve_race(boss.current_node_id, 1, 4)
	_expect(boss.current_map.act == 2 and boss.boot_cars.is_empty(), "act rival victory banks before advancing")
	var final_boss := _offer()
	final_boss.send_it_ahead()
	final_boss._advance_to_act(3)
	_move_to(final_boss, "act_rival")
	final_boss.resolve_race(final_boss.current_node_id, 1, 4)
	_expect(final_boss.completed and final_boss.boot_cars.is_empty(), "final rival banks before completing")
	var items := SESSION.create(2467)
	_expect(not items.spend_tow() and not items.spend_nitro(), "empty consumables cannot spend")
	_expect(items.add_tow(2) and items.add_tow(1) and items.add_nitro(3), "consumables stack")
	_expect(not items.add_tow(-1) and not items.add_nitro(0), "invalid additions do not mutate")
	_expect(items.spend_tow() and items.tow_count == 2 and items.spend_nitro() and items.nitro_count == 2, "spend uses exactly one")
	var item_load := SESSION.deserialize(SESSION.serialize(items))
	_expect(item_load != null and item_load.tow_count == 2 and item_load.nitro_count == 2, "consumables persist")
	_expect(not items.can_race_hot("unknown") and not items.hot_choice_reason("unknown").is_empty(), "unavailable hot choice explains why")
	var no_spare := _offer()
	var driver: Dictionary = no_spare.pending_offer_driver.duplicate(true)
	for act: String in no_spare.node_opponents:
		for node: String in no_spare.node_opponents[act]:
			for opponent: Dictionary in no_spare.node_opponents[act][node]["opponents"]:
				opponent["vehicle_id"] = driver["vehicle_id"]
	_expect(not no_spare.can_race_hot(no_spare.pending_offer) and not no_spare.race_it_now(), "no distinct same-band roster car disables hot choice")
	var lockup := SESSION.create(2467)
	_move_to(lockup, "lockup")
	lockup.open_lockup()
	_expect(not lockup.can_race_hot(lockup.pending_offer) and lockup.send_it_home(), "lockup has no robbed driver")
	if _failed:
		quit(1)
		return
	print("RUN_HAUL_TEST PASS")
	quit(0)

func _offer() -> RunSession:
	var sess := SESSION.create(33333)
	_move_to(sess, "rival")
	sess.resolve_rival(sess.current_node_id, true)
	return sess

func _move_to(sess: RunSession, kind: String) -> void:
	# Domain fixtures isolate stop operations from route choice/UI.
	for node: Dictionary in sess.current_map.nodes.values():
		if node["type"] == kind:
			sess.current_node_id = node["id"]
			sess.run_state.row = node["row"]
			if kind == "bench":
				sess.last_bench_visited = node["id"]
				sess.bench_action_done = false
			return
	_expect(false, "fixture stop exists: " + kind)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_HAUL_TEST FAIL: " + message)
