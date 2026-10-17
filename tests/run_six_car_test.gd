extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
var _failed := false

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var session := SESSION.create(33333)
	_expect(SESSION.RUN_POINTS_BY_FINISH == {1: 10, 2: 7, 3: 5, 4: 3, 5: 2, 6: 1}, "six places pay 10/7/5/3/2/1")
	for position: int in range(1, 7):
		var race := SESSION.create(33333)
		var outcome := race.resolve_race(race.current_node_id, position, 6)
		_expect(outcome["points_gained"] == SESSION.RUN_POINTS_BY_FINISH.get(position, -1), "finish pays its table entry")
	for act: String in session.node_opponents:
		var map := RunMap.generate(session.run_seed, int(act))
		for node: String in session.node_opponents[act]:
			var expected := 1 if map.nodes[node]["type"] == "rival" else 5
			_expect(session.node_opponents[act][node]["opponents"].size() == expected, "field has five opponents; duel has one")
	var loaded := SESSION.deserialize(JSON.parse_string(JSON.stringify(SESSION.serialize(session))))
	_expect(loaded != null and loaded.node_opponents == session.node_opponents, "six-car assignments survive JSON")
	if _failed:
		quit(1)
		return
	print("RUN_SIX_CAR_TEST PASS")
	quit(0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_SIX_CAR_TEST FAIL: " + message)
