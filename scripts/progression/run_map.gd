class_name RunMap
extends RefCounted

const SCHEMA_VERSION := 2
const NUM_COLUMNS := 7

const ACT_SPECS := {
	1: {"rows": 8, "paths": 5},
	2: {"rows": 9, "paths": 5},
	3: {"rows": 10, "paths": 6},
}

const QUOTAS := {
	"errand": 0.20,
	"bench": 0.12,
	"rival": 0.12,
	"parts_van": 0.08,
	"lockup": 0.06,
}

const HASH_INITIAL := 0x13579BDF
const HASH_MULTIPLIER := 1103515245
const HASH_ADD := 12345
const HASH_MASK := 0x7FFFFFFF

const COL_SALT := 0x434F4C4C
const DELTA_SALT := 0x44454C54
const TYPE_SALT := 0x54595045
const MAX_BUILD_ATTEMPTS := 256
const BOSS_COLUMN := NUM_COLUMNS / 2
const DEALT_TYPES: Array[String] = ["race", "errand", "parts_van", "rival", "bench", "lockup"]
const LATE_TYPES: Array[String] = ["rival", "bench", "lockup"]

var run_seed: int = 0
var act: int = 1
var num_rows: int = 0
var num_paths: int = 0
var path_count: int = 0
var nodes: Dictionary = {}
var parents: Dictionary = {}
var children: Dictionary = {}
var row_nodes: Array = []

static func get_act_spec(act: int) -> Dictionary:
	var a: int = clampi(act, 1, 3)
	var spec: Dictionary = ACT_SPECS.get(a, {"rows": 8, "paths": 5})
	return spec.duplicate(true)

static func _hash32(value: int) -> int:
	var mixed: int = value & HASH_MASK
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & HASH_MASK
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & HASH_MASK
	return (mixed ^ (mixed >> 16)) & HASH_MASK

static func _hash_unit(seed: int, salt: int) -> float:
	return float(_hash32(seed ^ salt)) / 2147483647.0

static func _derive(map_seed: int, row: int, label: String) -> int:
	var value: int = HASH_INITIAL
	var key: String = "pocket-circuit|run-map|v%d|seed=%d|row=%d|%s" % [SCHEMA_VERSION, map_seed, row, label]
	for b: int in key.to_utf8_buffer():
		value = (value * HASH_MULTIPLIER + b + HASH_ADD) & HASH_MASK
		value = (value ^ (value >> 11)) & HASH_MASK
	return value

static func _roll(map_seed: int, row: int, label: String, salt: int) -> float:
	var ds: int = _derive(map_seed, row, label)
	return _hash_unit(ds, salt)

static func _pick_col(map_seed: int, row: int, label: String) -> int:
	var u: float = _roll(map_seed, row, label, COL_SALT)
	return int(u * float(NUM_COLUMNS))

static func _unique_sorted(a: Array) -> Array[int]:
	var seen: Dictionary = {}
	for v: int in a:
		seen[v] = true
	var res: Array[int] = []
	for k: Variant in seen:
		res.append(int(k))
	res.sort()
	return res

static func _derive_map_seed(run_seed: int, act: int, jitter: int) -> int:
	var value: int = HASH_INITIAL
	var key: String = "pocket-circuit|run-map|mapseed|v%d|run=%d|act=%d|j=%d" % [SCHEMA_VERSION, run_seed, act, jitter]
	for b: int in key.to_utf8_buffer():
		value = (value * HASH_MULTIPLIER + b + HASH_ADD) & HASH_MASK
		value = (value ^ (value >> 11)) & HASH_MASK
	return value

static func _choose_delta(map_seed: int, r: int, p: int, n_rows: int, lane_target: int, current: int) -> int:
	var u: float = _roll(map_seed, r, "delta_p%d" % p, DELTA_SALT)
	var progress: float = float(r) / float(maxi(1, n_rows))
	var lane_bias: int = 0
	var lane_bstr: float = 0.0
	if progress < 0.60:
		var ldist: int = lane_target - current
		if ldist != 0:
			lane_bias = 1 if ldist > 0 else -1
			lane_bstr = 0.82 if progress < 0.25 else 0.65
	if lane_bias != 0 and u < lane_bstr:
		return lane_bias
	var uu: float = u
	if lane_bstr > 0.0:
		uu = (u - lane_bstr) / (1.0 - lane_bstr)
	return clampi(int(uu * 3.0) - 1, -1, 1)

## Walkers climb `rows` rows from one start node, one column step at a time,
## never crossing and freely merging. The top walker row is the act's benches;
## the act rival sits one row above them as the single end node every route
## reaches.
static func _try_build(map_seed: int, run_seed: int, act: int) -> Dictionary:
	var spec: Dictionary = get_act_spec(act)
	var walker_rows: int = int(spec["rows"])
	var n_paths: int = int(spec["paths"])
	var start_col: int = _pick_col(map_seed, 0, "start")
	var walker_lanes: Array[int] = []
	var lane_step: float = float(NUM_COLUMNS - 1) / float(maxi(1, n_paths - 1))
	for pp: int in range(n_paths):
		walker_lanes.append(clampi(int(round(float(pp) * lane_step)), 0, NUM_COLUMNS - 1))
	var walker_pos: Array = []
	var cur: Array[int] = []
	for __ in range(n_paths):
		cur.append(start_col)
	walker_pos.append(cur.duplicate())
	for r: int in range(walker_rows - 1):
		var nxt: Array[int] = []
		var prev_c: int = -999
		for p: int in range(n_paths):
			var pc: int = cur[p]
			var minr: int = clampi(pc - 1, 0, NUM_COLUMNS - 1)
			var maxr: int = clampi(pc + 1, 0, NUM_COLUMNS - 1)
			var cand: int = clampi(pc + _choose_delta(map_seed, r, p, walker_rows, walker_lanes[p], pc), 0, NUM_COLUMNS - 1)
			cand = clampi(maxi(cand, prev_c), minr, maxr)
			if r < int(float(walker_rows) * 0.5) and cand == prev_c and cand < maxr:
				cand += 1
			nxt.append(cand)
			prev_c = cand
		# Merging walkers must not collapse a whole choice row into one stop.
		if _unique_sorted(nxt).size() == 1:
			var merged: int = nxt[0]
			if merged > 0 and absi(cur[0] - (merged - 1)) <= 1:
				nxt[0] = merged - 1
			else:
				nxt[n_paths - 1] = merged + 1
		cur = nxt
		walker_pos.append(cur.duplicate())
	var traj_set: Dictionary = {}
	for p: int in range(n_paths):
		var traj: Array[int] = []
		for rr: int in range(walker_rows):
			traj.append(walker_pos[rr][p])
		traj_set["|".join(traj)] = true
	if traj_set.size() != n_paths:
		return {}
	var rows_cols: Array = []
	for posrow: Array in walker_pos:
		rows_cols.append(_unique_sorted(posrow))
	var nds: Dictionary = {}
	for r: int in range(walker_rows):
		for c: int in rows_cols[r]:
			var idd: String = "%d_%d" % [r, c]
			nds[idd] = {"id": idd, "row": r, "col": c, "type": "race"}
	var chlds: Dictionary = {}
	var prnts: Dictionary = {}
	for r: int in range(walker_rows - 1):
		for p: int in range(n_paths):
			_link(chlds, prnts, "%d_%d" % [r, walker_pos[r][p]], "%d_%d" % [r + 1, walker_pos[r + 1][p]])
	# Add local forks only where they do not cross an existing route. Outer
	# lanes can still have one exit when a second would cross another lane.
	for r: int in range(walker_rows - 1):
		for c: int in rows_cols[r]:
			var pid := "%d_%d" % [r, c]
			if (chlds.get(pid, []) as Array).size() >= 2:
				continue
			for next_col: int in rows_cols[r + 1]:
				if absi(c - next_col) > 1:
					continue
				var crosses := false
				for peer_col: int in rows_cols[r]:
					for child_id: String in chlds.get("%d_%d" % [r, peer_col], []):
						if (c - peer_col) * (next_col - int(nds[child_id]["col"])) < 0:
							crosses = true
				if not crosses:
					_link(chlds, prnts, pid, "%d_%d" % [r + 1, next_col])
	# The forced bench row has no alternative type to deal. Keep one exit per
	# parent there rather than presenting identical repair choices.
	for c: int in rows_cols[walker_rows - 2]:
		var pid := "%d_%d" % [walker_rows - 2, c]
		var exits: Array = chlds[pid]
		var kept: String = exits[0]
		for cid: String in exits:
			if absi(int(nds[cid]["col"]) - c) < absi(int(nds[kept]["col"]) - c):
				kept = cid
		for cid: String in exits.duplicate():
			if cid != kept:
				exits.erase(cid)
				(prnts[cid] as Array).erase(pid)
	for c: int in (rows_cols[walker_rows - 1] as Array).duplicate():
		var nid := "%d_%d" % [walker_rows - 1, c]
		if (prnts.get(nid, []) as Array).is_empty():
			nds.erase(nid)
			prnts.erase(nid)
			(rows_cols[walker_rows - 1] as Array).erase(c)
	if (rows_cols[walker_rows - 1] as Array).size() < 2:
		return {}
	var boss_row: int = walker_rows
	var boss_id: String = "%d_%d" % [boss_row, BOSS_COLUMN]
	nds[boss_id] = {"id": boss_id, "row": boss_row, "col": BOSS_COLUMN, "type": "act_rival"}
	for c: int in rows_cols[walker_rows - 1]:
		_link(chlds, prnts, "%d_%d" % [walker_rows - 1, c], boss_id)
	rows_cols.append([BOSS_COLUMN])
	var typed: Dictionary = _assign_types(nds, prnts, rows_cols, map_seed, walker_rows)
	if typed.is_empty():
		return {}
	return {
		"run_seed": run_seed,
		"act": act,
		"num_rows": walker_rows + 1,
		"num_paths": n_paths,
		"path_count": traj_set.size(),
		"rows": rows_cols,
		"nodes": typed,
		"parents": prnts,
		"children": chlds,
	}

static func _link(chlds: Dictionary, prnts: Dictionary, pid: String, cid: String) -> void:
	if not chlds.has(pid): chlds[pid] = []
	if not (chlds[pid] as Array).has(cid): (chlds[pid] as Array).append(cid)
	if not prnts.has(cid): prnts[cid] = []
	if not (prnts[cid] as Array).has(pid): (prnts[cid] as Array).append(pid)

## Row 0 is the opening race, the top walker row is all benches and the row
## above it is the act rival. Rows in between are dealt from QUOTAS under the
## edge rules: no special repeats its parent's type, siblings never share a
## type, nothing valuable below the first third, no bench right under the
## bench row.
static func _assign_types(base_nodes: Dictionary, prnts: Dictionary, rows_cols: Array, map_seed: int, walker_rows: int) -> Dictionary:
	var typed: Dictionary = {}
	for k: String in base_nodes:
		typed[k] = (base_nodes[k] as Dictionary).duplicate(true)
	var bench_row: int = walker_rows - 1
	for c: int in rows_cols[bench_row]:
		typed["%d_%d" % [bench_row, c]]["type"] = "bench"
	var dealt_total: int = 0
	for r: int in range(1, bench_row):
		dealt_total += (rows_cols[r] as Array).size()
	var target: Dictionary = {}
	for t: String in QUOTAS:
		target[t] = int(round(QUOTAS[t] * float(dealt_total)))
	target["parts_van"] = maxi(1, int(target["parts_van"]))
	# Each act has a middle-row van after the opening payout and before the
	# final bench/rival. Points earned earlier therefore have a spending route;
	# taking that route is optional, not an automatic purchase or forced visit.
	var van_row := walker_rows / 2
	var van_cols: Array = rows_cols[van_row]
	var van_col: int = van_cols[_derive(map_seed, van_row, "van") % van_cols.size()]
	var cur_count: Dictionary = {}
	var min_spec_row: int = int(float(walker_rows) * 0.333)
	for r: int in range(1, bench_row):
		var sib_used: Dictionary = {}
		for c: int in rows_cols[r]:
			var nid: String = "%d_%d" % [r, c]
			var forbid: Array = []
			var pars: Array = prnts.get(nid, [])
			for pid: String in pars:
				var pty: String = String((typed[pid] as Dictionary).get("type", "race"))
				if pty != "race" and not forbid.has(pty): forbid.append(pty)
				for st: String in (sib_used.get(pid, []) as Array):
					if not forbid.has(st): forbid.append(st)
			var allowed: Array = []
			for t: String in DEALT_TYPES:
				if forbid.has(t): continue
				if t == "parts_van" and (r < van_row or (r == van_row and c != van_col)): continue
				if r < min_spec_row and t in LATE_TYPES: continue
				if t == "bench" and r == bench_row - 1: continue
				allowed.append(t)
			if allowed.is_empty():
				return {}
			var cands: Array = []
			var defic: Dictionary = {}
			for t: String in allowed:
				var tg: int = int(target.get(t, 0))
				var cc: int = int(cur_count.get(t, 0))
				if t == "race" or cc < tg:
					cands.append(t)
					if t != "race":
						defic[t] = float(tg - cc) / float(maxi(1, tg))
			if cands.is_empty():
				cands = [allowed[0]]
			cands.sort_custom(func(aa: String, bb: String) -> bool:
				var da: float = float(defic.get(aa, 0.0))
				var db: float = float(defic.get(bb, 0.0))
				if da != db: return da > db
				return aa < bb
			)
			var pu: float = _roll(map_seed, r, "pick_c%d" % c, TYPE_SALT)
			var idx: int = 0 if (pu < 0.55 and float(defic.get(cands[0], 0.0)) > 0.0) else int(pu * float(cands.size()))
			var chosen: String = String(cands[clampi(idx, 0, cands.size() - 1)])
			if r == van_row and c == van_col:
				if not allowed.has("parts_van"):
					return {}
				chosen = "parts_van"
			typed[nid]["type"] = chosen
			cur_count[chosen] = int(cur_count.get(chosen, 0)) + 1
			for pid: String in pars:
				if not sib_used.has(pid): sib_used[pid] = []
				(sib_used[pid] as Array).append(chosen)
	return typed

static func generate(run_seed: int, act: int) -> RunMap:
	var rs: int = posmod(run_seed, 0x7FFFFFFF)
	var a: int = clampi(act, 1, 3)
	for j: int in range(MAX_BUILD_ATTEMPTS):
		var built: Dictionary = _try_build(_derive_map_seed(rs, a, j), rs, a)
		if built.is_empty():
			continue
		var rm := new()
		rm.run_seed = rs
		rm.act = a
		rm.num_rows = int(built["num_rows"])
		rm.num_paths = int(built["num_paths"])
		rm.path_count = int(built["path_count"])
		rm.nodes = (built["nodes"] as Dictionary).duplicate(true)
		rm.parents = (built["parents"] as Dictionary).duplicate(true)
		rm.children = (built["children"] as Dictionary).duplicate(true)
		rm._index_rows()
		return rm
	# Every attempt failed: return null so the caller fails loudly.
	return null

func _index_rows() -> void:
	row_nodes = []
	for rr: int in range(num_rows):
		var lst: Array[Dictionary] = []
		for nid: String in nodes:
			var n: Dictionary = nodes[nid]
			if int(n.get("row", -1)) == rr:
				lst.append(n.duplicate(true))
		lst.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("col", 0)) < int(y.get("col", 0)))
		row_nodes.append(lst)

func get_node(node_id: String) -> Dictionary:
	if nodes.has(node_id):
		return (nodes[node_id] as Dictionary).duplicate(true)
	return {}

func get_nodes_in_row(r: int) -> Array[Dictionary]:
	if r < 0 or r >= num_rows or r >= row_nodes.size():
		return []
	var out: Array[Dictionary] = []
	for n: Dictionary in (row_nodes[r] as Array):
		out.append(n.duplicate(true))
	return out

func get_children(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chs: Array = children.get(node_id, [])
	for cid: String in chs:
		var nn: Dictionary = get_node(cid)
		if not nn.is_empty():
			out.append(nn)
	return out

func get_parents(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ps: Array = parents.get(node_id, [])
	for pid: String in ps:
		var nn: Dictionary = get_node(pid)
		if not nn.is_empty():
			out.append(nn)
	return out

func get_start_node() -> Dictionary:
	var r0: Array[Dictionary] = get_nodes_in_row(0)
	return r0[0] if r0.size() > 0 else {}

func get_end_node() -> Dictionary:
	var rl: Array[Dictionary] = get_nodes_in_row(num_rows - 1)
	return rl[0] if rl.size() > 0 else {}

func get_node_at(row: int, col: int) -> Dictionary:
	var nid: String = "%d_%d" % [row, col]
	return get_node(nid)

func is_first_row(r: int) -> bool:
	return r == 0

func is_last_row(r: int) -> bool:
	return r == num_rows - 1

static func serialize(rm: RunMap) -> Dictionary:
	if rm == null: return {}
	var ndata: Dictionary = {}
	for nid: String in rm.nodes:
		var n: Dictionary = rm.nodes[nid]
		ndata[nid] = {"row": int(n.get("row", 0)), "col": int(n.get("col", 0)), "type": String(n.get("type", "race"))}
	return {
		"schema_version": SCHEMA_VERSION,
		"run_seed": rm.run_seed,
		"act": rm.act,
		"num_rows": rm.num_rows,
		"num_paths": rm.num_paths,
		"path_count": rm.path_count,
		"nodes": ndata,
		"parents": rm.parents.duplicate(true),
		"children": rm.children.duplicate(true),
	}

static func deserialize(data: Dictionary) -> RunMap:
	if not is_integer(data.get("schema_version"), SCHEMA_VERSION, SCHEMA_VERSION):
		return null
	if not is_integer(data.get("run_seed"), 0, HASH_MASK) or not is_integer(data.get("act"), 1, ACT_SPECS.size()):
		return null
	var spec: Dictionary = ACT_SPECS[int(data["act"])]
	var rows: int = spec["rows"] + 1
	var paths: int = spec["paths"]
	if not is_integer(data.get("num_rows"), rows, rows) or not is_integer(data.get("num_paths"), paths, paths) or not is_integer(data.get("path_count"), paths, paths):
		return null
	for key: String in ["nodes", "parents", "children"]:
		if data.get(key) is not Dictionary:
			return null
	var ndin: Dictionary = data["nodes"]
	if ndin.is_empty() or ndin.size() > rows * NUM_COLUMNS:
		return null
	var rm := new()
	rm.run_seed = int(data["run_seed"])
	rm.act = int(data["act"])
	rm.num_rows = rows
	rm.num_paths = paths
	rm.path_count = paths
	for nid: Variant in ndin:
		var value: Variant = ndin[nid]
		if nid is not String or value is not Dictionary:
			return null
		var d: Dictionary = value
		if not is_integer(d.get("row"), 0, rows - 1) or not is_integer(d.get("col"), 0, NUM_COLUMNS - 1):
			return null
		var row: int = int(d["row"])
		var col: int = int(d["col"])
		var kind: Variant = d.get("type")
		if nid != "%d_%d" % [row, col] or kind is not String or (kind not in DEALT_TYPES and kind != "act_rival"):
			return null
		if (kind == "act_rival") != (row == rows - 1) or (row == 0 and kind != "race"):
			return null
		rm.nodes[nid] = {"id": nid, "row": row, "col": col, "type": kind}
	rm.parents = data["parents"].duplicate(true)
	rm.children = data["children"].duplicate(true)
	if not rm._valid_edges(rm.children, rm.parents, 1) or not rm._valid_edges(rm.parents, rm.children, -1):
		return null
	rm._index_rows()
	if rm.get_nodes_in_row(0).size() != 1 or rm.get_nodes_in_row(rows - 1).size() != 1:
		return null
	if int(rm.get_end_node()["col"]) != BOSS_COLUMN:
		return null
	return rm

## JSON represents numbers as floats; only exact, finite integers may become indices.
static func is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	return value is float and is_finite(value) and value == floor(value) and value >= minimum and value <= maximum

func _valid_edges(edges: Dictionary, reverse: Dictionary, direction: int) -> bool:
	for source: Variant in edges:
		if source is not String or not nodes.has(source) or edges[source] is not Array:
			return false
		var seen := {}
		for target: Variant in edges[source]:
			if target is not String or not nodes.has(target) or seen.has(target):
				return false
			if nodes[target]["row"] != nodes[source]["row"] + direction:
				return false
			if maxi(nodes[target]["row"], nodes[source]["row"]) < num_rows - 1 and absi(nodes[target]["col"] - nodes[source]["col"]) > 1:
				return false
			var back: Variant = reverse.get(target)
			if back is not Array or not back.has(source):
				return false
			seen[target] = true
	for nid: String in nodes:
		var row: int = nodes[nid]["row"]
		var endpoint := row == (num_rows - 1 if direction == 1 else 0)
		var links: Array = edges.get(nid, [])
		if links.is_empty() != endpoint:
			return false
	return true

static func _maps_structurally_equal(a: RunMap, b: RunMap) -> bool:
	if a.run_seed != b.run_seed or a.act != b.act or a.num_rows != b.num_rows or a.path_count != b.path_count: return false
	if a.nodes.size() != b.nodes.size(): return false
	for nid: String in a.nodes:
		if not b.nodes.has(nid): return false
		var na: Dictionary = a.nodes[nid]
		var nb: Dictionary = b.nodes[nid]
		if int(na.get("row", -1)) != int(nb.get("row", -1)) or int(na.get("col", -1)) != int(nb.get("col", -1)) or String(na.get("type", "")) != String(nb.get("type", "")): return false
	if a.children.size() != b.children.size(): return false
	for pid: String in a.children:
		if not b.children.has(pid): return false
		var ca: Array = a.children[pid]
		var cb: Array = b.children[pid]
		if ca.size() != cb.size(): return false
		for c in ca:
			if not cb.has(c): return false
	return true
