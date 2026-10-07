extends SceneTree

const RUN_MAP := preload("res://scripts/progression/run_map.gd")

const CORPUS_SIZE := 200
const QUOTA_TOL := 0.07

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for a: int in [1, 2, 3]:
		if not _check_act(a):
			return
	var m1a = RUN_MAP.generate(777777, 1)
	var m1b = RUN_MAP.generate(777777, 1)
	if not _expect(RUN_MAP._maps_structurally_equal(m1a, m1b), "same seed act 1 is deterministic"):
		return
	print("RUN_MAP_TEST PASS")
	quit(0)


func _check_act(a: int) -> bool:
	var spec: Dictionary = RUN_MAP.get_act_spec(a)
	var walker_rows: int = int(spec["rows"])
	var target_paths: int = int(spec["paths"])
	var bench_row: int = walker_rows - 1
	var boss_row: int = walker_rows
	var min_spec_row: int = int(float(walker_rows) * 0.333)
	var dealt_counts: Dictionary = {}
	var dealt_total: int = 0
	for i: int in CORPUS_SIZE:
		var s: int = 424242 + a * 100000 + i * 17
		var m = RUN_MAP.generate(s, a)
		var tag := "act %d seed %d" % [a, s]
		if not _expect(m != null, "generate returns a map (%s)" % tag):
			return false
		if not _expect(m.run_seed == posmod(s, 0x7FFFFFFF) and m.act == a, "seed and act retained (%s)" % tag):
			return false
		if not _expect(m.num_rows == walker_rows + 1 and m.num_paths == target_paths, "walker rows plus the act rival row (%s)" % tag):
			return false
		if not _expect(m.path_count >= target_paths, "path count %d >= %d (%s)" % [m.path_count, target_paths, tag]):
			return false
		var start: Dictionary = m.get_start_node()
		if not _expect(String(start.get("type", "")) == "race" and int(start.get("row", -1)) == 0, "row 0 opens on a race (%s)" % tag):
			return false
		var boss_nodes: Array[Dictionary] = m.get_nodes_in_row(boss_row)
		if not _expect(boss_nodes.size() == 1 and String(boss_nodes[0].get("type", "")) == "act_rival" and int(boss_nodes[0].get("col", -1)) == RUN_MAP.BOSS_COLUMN, "the top row is the single centred act rival (%s)" % tag):
			return false
		var boss_id := String(boss_nodes[0]["id"])
		if not _expect(String(m.get_end_node().get("id", "")) == boss_id and not m.children.has(boss_id), "the act rival ends the act (%s)" % tag):
			return false
		var benches: Array[Dictionary] = m.get_nodes_in_row(bench_row)
		for bench: Dictionary in benches:
			if not _expect(String(bench.get("type", "")) == "bench", "the row under the act rival is all benches (%s)" % tag):
				return false
			if not _expect(m.children.get(String(bench["id"]), []) == [boss_id], "every bench leads only to the act rival (%s)" % tag):
				return false
		if not _expect((m.parents.get(boss_id, []) as Array).size() == benches.size(), "every bench reaches the act rival (%s)" % tag):
			return false
		for nid: String in m.nodes:
			var n: Dictionary = m.get_node(nid)
			var rr: int = int(n["row"])
			var t: String = String(n["type"])
			if not _expect(rr >= 0 and rr <= boss_row and int(n["col"]) >= 0 and int(n["col"]) < RUN_MAP.NUM_COLUMNS, "node inside the grid (%s)" % tag):
				return false
			if not _expect((t == "act_rival") == (rr == boss_row), "act rival only on its own row (%s)" % tag):
				return false
			if rr == 0 or rr >= bench_row:
				continue
			if not _expect(not (t in RUN_MAP.LATE_TYPES and rr < min_spec_row), "%s below the first third at row %d (%s)" % [t, rr, tag]):
				return false
			if not _expect(not (t == "bench" and rr == bench_row - 1), "no bench right under the bench row (%s)" % tag):
				return false
			dealt_counts[t] = int(dealt_counts.get(t, 0)) + 1
			dealt_total += 1
		for pid: String in m.children:
			var p: Dictionary = m.get_node(pid)
			for cid: String in (m.children[pid] as Array):
				var c: Dictionary = m.get_node(cid)
				if not _expect(int(c["row"]) == int(p["row"]) + 1, "edges climb one row (%s)" % tag):
					return false
				if cid != boss_id and not _expect(absi(int(c["col"]) - int(p["col"])) <= 1, "walker edges move one column at most (%s)" % tag):
					return false
		if not _expect(_no_crossing(m), "edges never cross (%s)" % tag):
			return false
		if not _expect(_edge_rules_hold(m, bench_row), "parent and sibling type rules (%s)" % tag):
			return false
		if not _expect(RUN_MAP._maps_structurally_equal(m, RUN_MAP.generate(s, a)), "deterministic (%s)" % tag):
			return false
		if not _expect(RUN_MAP._maps_structurally_equal(m, RUN_MAP.deserialize(RUN_MAP.serialize(m))), "serialize round trip (%s)" % tag):
			return false
	for t: String in RUN_MAP.QUOTAS:
		var observed: float = float(dealt_counts.get(t, 0)) / float(maxi(1, dealt_total))
		var wanted: float = float(RUN_MAP.QUOTAS[t])
		if not _expect(absf(observed - wanted) <= QUOTA_TOL, "quota %s act %d observed %.3f wanted %.2f over %d dealt nodes" % [t, a, observed, wanted, dealt_total]):
			return false
	return true


func _no_crossing(m) -> bool:
	for r: int in range(m.num_rows - 1):
		var edges: Array = []
		for parent: Dictionary in m.get_nodes_in_row(r):
			for child: Dictionary in m.get_children(String(parent["id"])):
				edges.append([int(parent["col"]), int(child["col"])])
		edges.sort()
		for i: int in range(1, edges.size()):
			if edges[i][1] < edges[i - 1][1]:
				return false
	return true


## Specials never repeat their parent's type and siblings never share one; the
## forced bench row is exempt from the sibling rule.
func _edge_rules_hold(m, bench_row: int) -> bool:
	for pid: String in m.children:
		var ptype := String(m.get_node(pid)["type"])
		var seen: Dictionary = {}
		for child: Dictionary in m.get_children(pid):
			var ct := String(child["type"])
			if ct != "race" and ct == ptype:
				return false
			if int(child["row"]) != bench_row and seen.has(ct):
				return false
			seen[ct] = true
	return true


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		print("FAIL: ", message)
		quit(1)
	return condition
