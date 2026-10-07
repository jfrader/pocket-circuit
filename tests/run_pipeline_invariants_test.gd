extends SceneTree

const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
const RUN_MAP := preload("res://scripts/progression/run_map.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")
const APP := preload("res://scripts/autoload/app.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

var _failed := false
func _expect(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
	return cond

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	_test_map_invariants()
	if _failed: quit(1); return
	
	_test_double_resolutions()
	if _failed: quit(1); return
	
	_test_save_failures()
	if _failed: quit(1); return
	
	_test_deserialize_mismatch()
	if _failed: quit(1); return
	
	print("RUN_PIPELINE_INVARIANTS_TEST PASS")
	quit(0)

func _test_map_invariants() -> void:
	var boss_count := 0
	var total := 0
	for act in range(1, 4):
		for seed_idx in range(200):
			total += 1
			var rm = RUN_MAP.generate(seed_idx, act)
			if not _expect(rm != null, "map generated successfully (no silent fallback return)"):
				return
			var has_boss := false
			for nid: String in rm.nodes:
				var node: Dictionary = rm.nodes[nid]
				if String(node.get("type", "")) == "act_rival":
					has_boss = true
					# Check it is NOT a sole child
					var parents = rm.parents.get(nid, [])
					var is_sole := false
					for p in parents:
						if rm.children.get(p, []).size() == 1:
							is_sole = true
							break
					if not _expect(not is_sole, "act_rival %s must not be a sole child (seed %d, act %d)" % [nid, seed_idx, act]):
						return
			if has_boss:
				boss_count += 1
	print("Boss-present rate: %d / %d (%.1f%%)" % [boss_count, total, 100.0 * boss_count / float(maxi(1, total))])

func _test_double_resolutions() -> void:
	# Test spend
	var sess1 = RUN_SESSION.create(100)
	sess1.current_node_id = "test_node"
	sess1.run_budget = 60
	sess1.current_map.nodes["test_node"] = {"id": "test_node", "type": "parts_van"}
	var s1 = sess1.spend(10)
	if not _expect(s1, "first spend ok"): return
	if not _expect(sess1.run_budget == 50, "budget reduced"): return
	var s2 = sess1.spend(10)
	if not _expect(not s2, "second spend refused"): return
	if not _expect(sess1.run_budget == 50, "budget not reduced again"): return
	
	var sess_saved = RUN_SESSION.deserialize(RUN_SESSION.serialize(sess1))
	var s3 = sess_saved.spend(10)
	if not _expect(not s3, "spend still refused after save/load roundtrip"): return
	
	# Test resolve_race
	var sess2 = RUN_SESSION.create(101)
	sess2.current_node_id = "test_race"
	sess2.current_map.nodes["test_race"] = {"id": "test_race", "type": "race"}
	var r1 = sess2.resolve_race("test_race", 1, 4)
	if not _expect(not r1.has("error"), "first race resolve ok"): return
	if not _expect(sess2.run_points == 6, "points awarded"): return
	var r2 = sess2.resolve_race("test_race", 1, 4)
	if not _expect(r2.has("error"), "second race resolve refused"): return
	if not _expect(sess2.run_points == 6, "points not awarded again"): return

func _test_save_failures() -> void:
	var app = APP.new()
	var store = SAVE_STORE.new()
	app._save_store = store
	app._current_run_session = RUN_SESSION.create(200)
	
	# Test refused node (wrong type)
	var ok = app.run_spend(10, "")
	if not _expect(not ok, "seam refused due to wrong type"): return
	if not _expect(app.last_run_error != "", "last_run_error is non-empty on refusal: " + app.last_run_error): return
	
	app._current_run_session.current_map.nodes[app._current_run_session.current_node_id]["type"] = "parts_van"
	ok = app.run_spend(10, "")
	if not _expect(ok, "seam accepted"): return
	if not _expect(app.last_run_error == "", "last_run_error cleared on success"): return
	
	# Test read-only save
	store.is_read_only = true
	app._current_run_session.resolved_nodes.clear()
	app._current_run_session.current_map.nodes[app._current_run_session.current_node_id]["type"] = "parts_van"
	ok = app.run_spend(10, "") # budget is enough
	if not _expect(ok, "seam accepted logically"): return
	if not _expect(app.last_run_error != "", "last_run_error is non-empty on read-only save: " + app.last_run_error): return
	
	app.free()

func _test_deserialize_mismatch() -> void:
	var data = {"schema_version": 9999}
	var res1 = RUN_MAP.deserialize(data)
	if not _expect(res1 == null, "RunMap deserialize mismatch returns null"): return
	var res2 = RUN_STATE.deserialize(data)
	if not _expect(res2 == null, "RunState deserialize mismatch returns null"): return
	var res3 = RUN_SESSION.deserialize(data)
	if not _expect(res3 == null, "RunSession deserialize mismatch returns null"): return

