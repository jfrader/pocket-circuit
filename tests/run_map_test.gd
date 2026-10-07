extends SceneTree

const RUN_MAP := preload("res://scripts/progression/run_map.gd")

const CORPUS_SIZE := 200
const QUOTA_TOL := 0.07
const STRUCT_TOL := 0.0001

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var all_pass := true
	for a: int in [1, 2, 3]:
		var spec: Dictionary = RUN_MAP.get_act_spec(a)
		var target_rows: int = int(spec.get("rows", 8))
		var target_paths: int = int(spec.get("paths", 5))
		var min_spec_row: int = int(float(target_rows) * 0.333)
		var qcounts: Dictionary = {"errand": 0, "bench": 0, "rival": 0, "parts_van": 0, "lockup": 0, "act_rival": 0, "race": 0}
		var total_nodes_seen: int = 0
		var det_fail := 0
		var quota_over := {"errand": 0.0, "bench": 0.0, "rival": 0.0, "parts_van": 0.0, "lockup": 0.0}
		for i: int in CORPUS_SIZE:
			var s: int = 424242 + a * 100000 + i * 17
			var m = RUN_MAP.generate(s, a)
			if not _expect(m != null, "generate produced instance for act %d seed %d" % [a, s]):
				return
			if not _expect(m.run_seed == posmod(s, 0x7FFFFFFF) and m.act == a, "seed and act retained"):
				return
			if not _expect(m.num_rows == target_rows and m.num_paths == target_paths, "rows/paths match spec for act %d" % a):
				return
			# forced rows
			var sn: Dictionary = m.get_start_node()
			if not _expect(String(sn.get("type", "")) == "race" and int(sn.get("row", -1)) == 0, "row 0 forced race"):
				return
			var en: Dictionary = m.get_end_node()
			if not _expect(String(en.get("type", "")) == "bench" and int(en.get("row", -1)) == target_rows - 1, "last row forced bench"):
				return
			# bounds + structure
			var node_count: int = 0
			for nid: String in m.nodes:
				var n: Dictionary = m.get_node(nid)
				var rr: int = int(n.get("row", -1))
				var cc: int = int(n.get("col", -1))
				if not _expect(rr >= 0 and rr < target_rows and cc >= 0 and cc < 7, "node bounds row/col"):
					return
				node_count += 1
			total_nodes_seen += node_count
			# edges +-1 and forward only
			for pid: String in m.children:
				var p: Dictionary = m.get_node(pid)
				var ch: Array = m.children[pid]
				for cid: String in ch:
					var c: Dictionary = m.get_node(cid)
					if not _expect(int(c.get("row", -1)) == int(p.get("row", -1)) + 1, "edge only to next row"):
						return
					if not _expect(absi(int(c.get("col", -1)) - int(p.get("col", -1))) <= 1, "edge |dcol| <=1"):
						return
			# path count via local dp
			var start_id: String = "0_%d" % int(sn.get("col", 0))
			var end_id: String = "%d_%d" % [target_rows - 1, int(en.get("col", 0))]
			var w: Dictionary = {}
			w[start_id] = 1
			for rr: int in range(target_rows - 1):
				for ccc: int in range(7):
					var pid: String = "%d_%d" % [rr, ccc]
					if not m.nodes.has(pid) or not w.has(pid):
						continue
					var ww: int = int(w[pid])
					if m.children.has(pid):
						for cid: String in (m.children[pid] as Array):
							if not w.has(cid):
								w[cid] = 0
							w[cid] = int(w[cid]) + ww
			var pc: int = int(w.get(end_id, 0))
			if not _expect(m.path_count >= target_paths, "path count >= target %d (got %d) act %d" % [target_paths, m.path_count, a]):
				return
			# no crossing check (monotonic connections)
			if not _check_no_cross(m, target_rows):
				if not _expect(false, "no crossing edges act %d seed %d" % [a, s]):
					return
			# hard rules on types + early/late
			for nid: String in m.nodes:
				var n: Dictionary = m.get_node(nid)
				var t: String = String(n.get("type", ""))
				var rr: int = int(n.get("row", -1))
				if t in ["rival", "bench", "lockup", "act_rival"] and rr < min_spec_row:
					if not _expect(false, "banned special %s below 1/3 row %d act %d" % [t, rr, a]): return
				if t == "bench" and rr == target_rows - 2:
					if not _expect(false, "bench banned on pre-last row"): return
				if t == "race" and rr == target_rows - 1:
					if not _expect(false, "last not race"): return
			# parent-child no same for restricted; siblings unique
			if not _check_edge_rules(m):
				if not _expect(false, "edge/sibling type rules violated act %d seed %d" % [a, s]): return
			# quota accumulation
			for nid: String in m.nodes:
				var t: String = String(m.get_node(nid).get("type", "race"))
				if qcounts.has(t):
					qcounts[t] += 1
				else:
					qcounts["race"] = qcounts.get("race", 0) + 1
			# determinism
			var m2 = RUN_MAP.generate(s, a)
			if not RUN_MAP._maps_structurally_equal(m, m2):
				det_fail += 1
			# ser roundtrip
			var snap: Dictionary = RUN_MAP.serialize(m)
			var m3 = RUN_MAP.deserialize(snap)
			if not RUN_MAP._maps_structurally_equal(m, m3):
				if not _expect(false, "ser roundtrip failed act %d seed %d" % [a, s]): return
		# corpus quota check (within tol)
		for t: String in ["errand", "bench", "rival", "parts_van", "lockup"]:
			var obs: float = float(qcounts.get(t, 0)) / float(maxi(1, total_nodes_seen))
			var tgt: float = float(RUN_MAP.QUOTAS.get(t, 0.0))
			if not _expect(absf(obs - tgt) <= QUOTA_TOL, "quota %s act %d obs %.3f tgt %.2f over %d nodes" % [t, a, obs, tgt, total_nodes_seen]):
				return
		# act_rival consumed from rival budget, so rival+act_rival ~0.12
		var riv_total: float = float(qcounts.get("rival", 0) + qcounts.get("act_rival", 0)) / float(maxi(1, total_nodes_seen))
		if not _expect(absf(riv_total - 0.12) <= QUOTA_TOL + 0.02, "rival+act_rival ~0.12 act %d" % a):
			return
		if det_fail > 0:
			if not _expect(false, "determinism fails %d/%d act %d" % [det_fail, CORPUS_SIZE, a]): return
		# also quick check forced always even in fallback path
		var mfall = RUN_MAP.generate(999999, a)
		var fs: Dictionary = mfall.get_start_node()
		var fe: Dictionary = mfall.get_end_node()
		if not _expect(String(fs.get("type", "")) == "race" and String(fe.get("type", "")) == "bench", "fallback also forces"):
			return

	# cross act determinism spot
	var s0: int = 777777
	var m1a = RUN_MAP.generate(s0, 1)
	var m1b = RUN_MAP.generate(s0, 1)
	if not RUN_MAP._maps_structurally_equal(m1a, m1b):
		if not _expect(false, "same seed act1 det"): return

	print("RUN_MAP_TEST PASS")
	quit(0)

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		print("FAIL: ", message)
		quit(1)
		return false
	return true

func _check_no_cross(m, n_rows: int) -> bool:
	for r: int in range(n_rows - 1):
		var edges: Array = []
		for pid: String in m.children:
			var p: Dictionary = m.get_node(pid)
			if int(p.get("row", -1)) != r:
				continue
			for cid: String in (m.children[pid] as Array):
				var c: Dictionary = m.get_node(cid)
				edges.append([int(p.get("col", 0)), int(c.get("col", 0))])
		# sort by parent col
		edges.sort_custom(func(e1: Array, e2: Array) -> bool: return e1[0] < e2[0])
		for i: int in range(1, edges.size()):
			if edges[i][1] < edges[i-1][1]:
				return false  # crossed
	return true

func _check_edge_rules(m) -> bool:
	for pid: String in m.children:
		var p: Dictionary = m.get_node(pid)
		var ptype: String = String(p.get("type", ""))
		var seen_sib: Dictionary = {}
		for cid: String in (m.children[pid] as Array):
			var c: Dictionary = m.get_node(cid)
			var ct: String = String(c.get("type", ""))
			if ct in ["bench", "lockup", "parts_van", "rival", "act_rival"] and ct == ptype:
				return false
			if seen_sib.has(ct):
				return false
			seen_sib[ct] = true
	return true

func maxi(a: int, b: int) -> int:
	return a if a > b else b

func absi(x: int) -> int:
	return x if x >= 0 else -x
