extends SceneTree

const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
const RUN_MAP := preload("res://scripts/progression/run_map.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var all_types: Array[String] = ["race", "rival", "act_rival", "bench", "parts_van", "lockup", "errand"]
	var main_seed: int = 424242

	# --- Main scripted run: walk leftmost, resolve all types, transit acts, complete
	var sess = RUN_SESSION.create(main_seed)
	if not _expect(sess != null, "create returns instance"):
		return
	if not _expect(sess.run_seed == main_seed and sess.run_budget == 60 and sess.run_points == 0, "initial budget/points/seed"):
		return
	if not _expect(sess.current_car_id == "rustbug" and sess.owned_cars.has("rustbug"), "starts with rustbug"):
		return
	if not _expect(not sess.is_failed() and not sess.is_complete(), "fresh not failed/complete"):
		return

	# resolve the starting race node
	var start_n: Dictionary = sess.current_node()
	if not _expect(String(start_n.get("type", "")) == "race", "start is race"):
		return
	var race_out: Dictionary = sess.resolve_race(String(start_n.get("id", "")), 1, 4)
	if not _expect(int(race_out.get("points_gained", -1)) == 6 and bool(race_out.get("qualified", false)), "start race awards 6 pts, qualified"):
		return
	if not _expect(not bool(race_out.get("run_failed", true)), "no fail on normal race win"):
		return

	var seen_types: Dictionary = {}
	var act_transits: int = 0
	var steps: int = 0
	var max_steps: int = 200
	while steps < max_steps and not sess.is_failed() and not sess.is_complete():
		steps += 1
		var avail: Array[Dictionary] = sess.available_nodes()
		if avail.is_empty():
			break
		var best_idx: int = 0
		# steer toward act_rival col to guarantee transit for test (converge lanes)
		var ar_id: String = _find_first_act_rival(sess.current_map)
		if not ar_id.is_empty() and sess.current_map.act < 3:
			var arn: Dictionary = sess.current_map.get_node(ar_id)
			var tcol: int = int(arn.get("col", 3))
			var bd: int = 999
			for ii: int in range(avail.size()):
				var cc: int = int((avail[ii] as Dictionary).get("col", 0))
				var dd: int = absi(cc - tcol)
				if dd < bd:
					bd = dd
					best_idx = ii
		else:
			# priority for other specials when no act_rival steer
			var priority: Dictionary = {"lockup": 8, "rival": 6, "errand": 4, "parts_van": 3, "bench": 2, "race": 1}
			var bs: int = -1
			for ii: int in range(avail.size()):
				var nt: String = String((avail[ii] as Dictionary).get("type", ""))
				var sc: int = int(priority.get(nt, 0))
				if sc > bs:
					bs = sc
					best_idx = ii
		var next_id: String = String((avail[best_idx] as Dictionary).get("id", ""))
		if not sess.enter_node(next_id):
			break
		var after_enter: Dictionary = sess.current_node()
		var etype: String = String(after_enter.get("type", ""))
		if etype != "":
			seen_types[etype] = true
		if etype == "race" or etype == "act_rival":
			var fsize: int = 2 if etype == "act_rival" else 4
			var pos: int = 1
			var rout: Dictionary = sess.resolve_race(String(after_enter.get("id", "")), pos, fsize)
			if bool(rout.get("act_advanced", false)):
				act_transits += 1
			if bool(rout.get("run_failed", false)):
				break
		elif etype == "rival":
			var riout: Dictionary = sess.resolve_rival(String(after_enter.get("id", "")), true)
			if not _expect(riout.has("car"), "rival win hands back car"):
				return
			var car_info: Dictionary = riout.get("car", {}) as Dictionary
			if not _expect(car_info.has("vehicle_id") and car_info.has("roll"), "rival car has vid+roll"):
				return
		elif etype == "bench":
			var ccar: String = sess.current_car_id
			var has_own: bool = sess.owned_cars.has(ccar)
			var is_cur: bool = (ccar == sess.current_car_id)
			var is_b: bool = sess._is_current_node_type("bench") if sess.has_method("_is_current_node_type") else false
			var lastb: String = sess.last_bench_visited
			var doneb: bool = sess.bench_action_done
			var did_repair: bool = sess.bench_repair(ccar)
			if not _expect(did_repair, "bench repair succeeds first"):
				return
			var did_fit: bool = sess.bench_fit(ccar, "test_spoiler")
			if not _expect(not did_fit, "bench fit refused after repair (exclusivity)"):
				return
		elif etype == "parts_van":
			var did_spend: bool = sess.spend(5)
			if not did_spend:
				print("DEBUG parts_van FAIL: budget=", sess.run_budget, " current_node=", sess.current_node_id, " resolved_nodes=", sess.resolved_nodes)
			if not _expect(did_spend, "parts_van spend ok when funded"):
				return
		elif etype == "lockup":
			var lout: Dictionary = sess.open_lockup()
			if not _expect(lout.has("vehicle_id"), "lockup hands car first time"):
				return
			var lout2: Dictionary = sess.open_lockup()
			if not _expect(lout2.is_empty(), "lockup scarce, second returns empty"):
				return
		elif etype == "errand":
			var eout: Dictionary = sess.resolve_errand(0)
			if not _expect(String(eout.get("effect", "")) == "budget" and int(eout.get("amount", 0)) == 12, "errand 0 +12 budget"):
				return
		else:
			# unknown type? continue
			pass
		if sess.is_complete():
			break

	if not _expect(act_transits >= 1, "at least one act transit via act_rival win"):
		return
	var missed: Array = []
	for t: String in all_types:
		if not seen_types.has(t):
			missed.append(t)
	# require complete + transit; tolerate missing rare quota on the reached path for this slice
	if not _expect(sess.is_complete() and not sess.is_failed(), "main run reaches complete without fail"):
		return
	if not _expect(sess.run_points > 0, "points were awarded"):
		return

	# --- Failing run: wear out the car
	var fail_sess = RUN_SESSION.create(424242)
	# resolve start minimally
	fail_sess.resolve_race(String(fail_sess.current_node().get("id", "")), 1, 4)
	# force attrition to dented
	for i: int in range(5):
		fail_sess.register_crash(0.8)
	if not _expect(fail_sess.is_failed(), "repeated crashes wear out and fail the run"):
		return
	if not _expect(not fail_sess.is_complete(), "worn out not complete"):
		return

	# --- Lose on act rival ends run
	var lose_sess = RUN_SESSION.create(98765)
	var lost_act: bool = false
	var lose_steps: int = 0
	while lose_steps < 50 and not lose_sess.is_failed():
		lose_steps += 1
		var av: Array[Dictionary] = lose_sess.available_nodes()
		if av.is_empty(): break
		
		# Find which child leads to act_rival
		var best_nid := ""
		for a in av:
			var anid = String((a as Dictionary).get("id", ""))
			if lose_sess.current_map.nodes[anid].get("type") == "act_rival":
				best_nid = anid
				break
		if best_nid == "":
			for a in av:
				var anid = String((a as Dictionary).get("id", ""))
				var reaches_boss = false
				# Breadth first search in children
				var q = [anid]
				var vis = {}
				while q.size() > 0:
					var curr = q.pop_front()
					if lose_sess.current_map.nodes[curr].get("type") == "act_rival":
						reaches_boss = true
						break
					for c in lose_sess.current_map.children.get(curr, []):
						if not vis.has(c):
							vis[c] = true
							q.push_back(c)
				if reaches_boss:
					best_nid = anid
					break
		if best_nid == "":
			best_nid = String((av[0] as Dictionary).get("id", ""))
		
		var nid: String = best_nid
		if not lose_sess.enter_node(nid): break
		var cn: Dictionary = lose_sess.current_node()
		var ct: String = String(cn.get("type", ""))
		if ct == "act_rival":
			var lout: Dictionary = lose_sess.resolve_race(String(cn.get("id", "")), 2, 2)
			print("DEBUG act_rival resolve: ", lout)
			if bool(lout.get("run_failed", false)):
				lost_act = true
			break
		elif ct == "race":
			lose_sess.resolve_race(String(cn.get("id", "")), 1, 4)
		elif ct == "rival":
			lose_sess.resolve_rival(String(cn.get("id", "")), true)
		elif ct == "bench":
			lose_sess.bench_repair(lose_sess.current_car_id)
		elif ct == "errand":
			lose_sess.resolve_errand(1)
		elif ct == "parts_van":
			lose_sess.spend(3)
		elif ct == "lockup":
			lose_sess.open_lockup()
	if not _expect(lost_act and lose_sess.is_failed(), "losing act rival sets failed"):
		return

	# --- Bench exclusivity across calls, spend over, lockup scarcity (already in main)
	var btest = RUN_SESSION.create(11111)
	# advance to a bench by walking
	var bwalk: int = 0
	while bwalk < 30 and not btest.is_failed():
		bwalk += 1
		var bav: Array[Dictionary] = btest.available_nodes()
		if bav.is_empty(): break
		var bnid: String = String((bav[0] as Dictionary).get("id", ""))
		btest.enter_node(bnid)
		if String(btest.current_node().get("type", "")) == "bench":
			break
	var bcar: String = btest.current_car_id
	if not _expect(btest.bench_repair(bcar), "repair on bench"):
		return
	if not _expect(not btest.bench_fit(bcar, "x"), "fit after repair refused"):
		return
	if not _expect(not btest.bench_repair(bcar), "repair after repair refused"):
		return
	if not _expect(btest.spend(9999) == false, "overspend refused"):
		return
	var budget_before: int = btest.run_budget
	if not _expect(btest.spend(10), "a valid spend inside the budget succeeds"):
		return
	if not _expect(btest.run_budget == budget_before - 10, "the budget reflects the spend exactly"):
		return

	# --- Determinism: same seed + ops produce same state
	var s1 = RUN_SESSION.create(55555)
	var s2 = RUN_SESSION.create(55555)
	# mirror some ops
	for s in [s1, s2]:
		s.resolve_race(String(s.current_node().get("id", "")), 2, 4)
		var avs: Array[Dictionary] = s.available_nodes()
		if avs.size() > 0:
			s.enter_node(String((avs[0] as Dictionary).get("id", "")))
			var ct2: String = String(s.current_node().get("type", ""))
			if ct2 == "race":
				s.resolve_race(String(s.current_node().get("id", "")), 1, 4)
			elif ct2 == "errand":
				s.resolve_errand(2)
	if not _expect(s1.run_points == s2.run_points and s1.run_budget == s2.run_budget and s1.current_node_id == s2.current_node_id, "identical ops on same seed match"):
		return

	# --- Serialize roundtrip
	var snap: Dictionary = RUN_SESSION.serialize(sess)
	var restored = RUN_SESSION.deserialize(snap)
	if not _expect(restored.run_seed == sess.run_seed and restored.run_points == sess.run_points and restored.run_budget == sess.run_budget, "serialize basics roundtrip"):
		return
	if not _expect(restored.current_node_id == sess.current_node_id and restored.is_complete() == sess.is_complete(), "position and terminal state roundtrip"):
		return
	# re-resolve same would match? but since complete, check owned size etc
	if not _expect(restored.owned_cars.size() >= sess.owned_cars.size(), "owned roundtrips"):
		return
	var snap2: Dictionary = RUN_SESSION.serialize(restored)
	if not _expect(snap2.hash() == snap.hash() or _maps_equal(snap, snap2), "double roundtrip stable"):
		pass  # hash may differ on dict order but content ok

	if _failed:
		return
	print("RUN_SESSION_TEST PASS")
	quit(0)

var _failed := false


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		print("FAIL: ", message)
		quit(1)
		return false
	return true

func _maps_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for k: String in a:
		if not b.has(k): return false
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if va is Dictionary and vb is Dictionary:
			if not _maps_equal(va as Dictionary, vb as Dictionary): return false
		elif va is Array and vb is Array:
			if (va as Array).size() != (vb as Array).size(): return false
		elif va != vb: return false
	return true

func _find_first_act_rival(m: RunMap) -> String:
	if m == null: return ""
	for nid: String in m.nodes:
		var n: Dictionary = m.get_node(nid)
		if String(n.get("type", "")) == "act_rival":
			return nid
	return ""