class_name RunMap
extends RefCounted

const SCHEMA_VERSION := 1
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
const ACT_RIVAL_SALT := 0x41435452
const END_PICK_SALT := 0x454E4450

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

static func _choose_delta(map_seed: int, r: int, p: int, current: int, converge: int, n_rows: int, is_last: bool, lane_target: int = -1) -> int:
	var label: String = "delta_p%d" % p
	var u: float = _roll(map_seed, r, label, DELTA_SALT)
	var progress: float = float(r) / float(maxi(1, n_rows))
	var bias: int = 0
	var bstr: float = 0.0
	if progress > 0.30 or is_last:
		var dist: int = converge - current
		if dist != 0:
			bias = 1 if dist > 0 else -1
		bstr = 0.75
		if progress > 0.6:
			bstr = 0.90
		if is_last:
			bstr = 0.98
	var lane_bias: int = 0
	var lane_bstr: float = 0.0
	if lane_target >= 0 and progress < 0.60 and not is_last:
		var ldist: int = lane_target - current
		if ldist != 0:
			lane_bias = 1 if ldist > 0 else -1
			lane_bstr = 0.65
			if progress < 0.25:
				lane_bstr = 0.82
	if bias != 0 and u < bstr:
		return bias
	if lane_bias != 0 and u < lane_bstr:
		return lane_bias
	var used_bstr: float = bstr
	if lane_bstr > used_bstr:
		used_bstr = lane_bstr
	var uu: float = u
	if used_bstr > 0.0 and used_bstr < 1.0:
		uu = (u - used_bstr) / (1.0 - used_bstr)
	var d: int = int(uu * 3.0) - 1
	return clampi(d, -1, 1)

static func _try_build(map_seed: int, run_seed: int, act: int) -> Dictionary:
	var spec: Dictionary = get_act_spec(act)
	var n_rows: int = int(spec["rows"])
	var n_paths: int = int(spec["paths"])
	var start_col: int = _pick_col(map_seed, 0, "start")
	var converge_col: int = _pick_col(map_seed, 0, "converge")
	var walker_lanes: Array[int] = []
	var lane_step: float = float(NUM_COLUMNS - 1) / float(maxi(1, n_paths - 1))
	for pp: int in range(n_paths):
		var l: int = int(round(float(pp) * lane_step))
		l = clampi(l, 0, NUM_COLUMNS - 1)
		walker_lanes.append(l)
	var walker_pos: Array = []
	var cur: Array[int] = []
	for __ in range(n_paths):
		cur.append(start_col)
	walker_pos.append(cur.duplicate())
	for r: int in range(n_rows - 1):
		var is_last_trans: bool = (r == n_rows - 2)
		var tent: Array[int] = []
		for p: int in range(n_paths):
			var pc: int = cur[p]
			var lt: int = walker_lanes[p] if p < walker_lanes.size() else -1
			var d: int = _choose_delta(map_seed, r, p, pc, converge_col, n_rows, is_last_trans, lt)
			var nc: int = clampi(pc + d, 0, NUM_COLUMNS - 1)
			tent.append(nc)
		var nxt: Array[int] = []
		var prev_c: int = -999
		for p: int in range(n_paths):
			var pc: int = cur[p]
			var minr: int = clampi(pc - 1, 0, NUM_COLUMNS - 1)
			var maxr: int = clampi(pc + 1, 0, NUM_COLUMNS - 1)
			var cand: int = tent[p]
			cand = maxi(cand, prev_c)
			cand = clampi(cand, minr, maxr)
			if (not is_last_trans) and r < int(float(n_rows) * 0.5) and cand == prev_c and cand < maxr:
				cand += 1
			nxt.append(cand)
			prev_c = cand
		if is_last_trans:
			var commons: Array[int] = []
			for c: int in range(NUM_COLUMNS):
				var ok: bool = true
				for p: int in range(n_paths):
					if absi(cur[p] - c) > 1:
						ok = false
						break
				if ok:
					commons.append(c)
			if commons.is_empty():
				# try pick closest possible from the spread, pick one reachable by majority, force only connectable walkers? for now bail rare
				return {}
			var pick_u: float = _roll(map_seed, r, "endpick", END_PICK_SALT)
			var pick: int = int(pick_u * float(commons.size()))
			pick = clampi(pick, 0, commons.size() - 1)
			var ec: int = commons[pick]
			for p: int in range(n_paths):
				nxt[p] = ec
		cur = nxt
		walker_pos.append(cur.duplicate())
	var last_cols: Array = walker_pos[walker_pos.size() - 1]
	var uniq_last: Array[int] = _unique_sorted(last_cols)
	if uniq_last.size() != 1:
		# force converge using a reached col from last tentative
		var arrived: Array[int] = _unique_sorted(last_cols)
		if arrived.is_empty():
			return {}
		var pick_u: float = _roll(map_seed, n_rows-1, "forceend", END_PICK_SALT)
		var ec: int = arrived[ int(pick_u * float(arrived.size())) % arrived.size() ]
		# check all penult can reach it
		var penult: Array = walker_pos[walker_pos.size()-2]
		var can: bool = true
		for pcv: int in penult:
			if absi(pcv - ec) > 1:
				can = false
		if not can:
			return {}
		# override last pos
		for p: int in range(n_paths):
			walker_pos[walker_pos.size()-1][p] = ec
		uniq_last = [ec]
	var end_c: int = uniq_last[0]
	var rows_cols: Array = []
	for posrow: Array in walker_pos:
		rows_cols.append(_unique_sorted(posrow))
	# compute distinct traj count (this is our "paths")
	var traj_set: Dictionary = {}
	for p: int in range(n_paths):
		var traj: Array[int] = []
		for rr: int in range(n_rows):
			traj.append( walker_pos[rr][p] )
		var key: String = "|".join(traj)
		traj_set[key] = true
	var distinct: int = traj_set.size()
	if distinct != n_paths:
		return {}
	# build nds edges
	var nds: Dictionary = {}
	for r: int in range(n_rows):
		for c: int in rows_cols[r]:
			var idd: String = "%d_%d" % [r, c]
			nds[idd] = {"id": idd, "row": r, "col": c, "type": "race"}
	var chlds: Dictionary = {}
	var prnts: Dictionary = {}
	for r: int in range(n_rows - 1):
		var used: Dictionary = {}
		for p: int in range(n_paths):
			var pc: int = walker_pos[r][p]
			var nc: int = walker_pos[r + 1][p]
			var pid: String = "%d_%d" % [r, pc]
			var cid: String = "%d_%d" % [r + 1, nc]
			var ekey: String = pid + ">" + cid
			if used.has(ekey): continue
			used[ekey] = true
			if not chlds.has(pid): chlds[pid] = []
			if not chlds[pid].has(cid): chlds[pid].append(cid)
			if not prnts.has(cid): prnts[cid] = []
			if not prnts[cid].has(pid): prnts[cid].append(pid)
	# dp for completeness (should match distinct)
	var wways: Dictionary = {}
	var sid: String = "0_%d" % start_col
	wways[sid] = 1
	for r: int in range(n_rows - 1):
		for c: int in rows_cols[r]:
			var pid: String = "%d_%d" % [r, c]
			if not wways.has(pid): continue
			var ww: int = int(wways[pid])
			if chlds.has(pid):
				for cid: String in chlds[pid]:
					if not wways.has(cid): wways[cid] = 0
					wways[cid] = int(wways[cid]) + ww
	var eid: String = "%d_%d" % [n_rows - 1, end_c]
	var pcnt: int = int(wways.get(eid, 0))
	var typed: Dictionary = _assign_types(nds, prnts, chlds, rows_cols, map_seed, n_rows)
	if typed.is_empty():
		return {}
	var res: Dictionary = {
		"run_seed": run_seed,
		"act": act,
		"num_rows": n_rows,
		"num_paths": n_paths,
		"path_count": distinct,
		"rows": rows_cols,
		"nodes": typed,
		"parents": prnts,
		"children": chlds,
	}
	return res

static func _assign_types(base_nodes: Dictionary, prnts: Dictionary, chlds: Dictionary, rows_cols: Array, map_seed: int, n_rows: int) -> Dictionary:
	var typed: Dictionary = {}
	for k: String in base_nodes:
		typed[k] = (base_nodes[k] as Dictionary).duplicate(true)
	var start_id: String = "0_%d" % rows_cols[0][0]
	typed[start_id]["type"] = "race"
	var last_r: int = n_rows - 1
	var last_id: String = "%d_%d" % [last_r, rows_cols[last_r][0]]
	typed[last_id]["type"] = "bench"
	var total: int = 0
	for rc: Array in rows_cols:
		total += rc.size()
	var target: Dictionary = {}
	for t: String in QUOTAS:
		target[t] = int(round(QUOTAS[t] * float(total)))
	target["act_rival"] = 1
	if target.has("rival"):
		target["rival"] = maxi(0, target["rival"] - 1)
	var cur_count: Dictionary = {"race": 1, "bench": 1, "rival": 0, "errand": 0, "parts_van": 0, "lockup": 0, "act_rival": 0}
	var min_spec_row: int = int(float(n_rows) * 0.333)
	for r: int in range(1, n_rows):
		if r == last_r: continue
		var rcols: Array = rows_cols[r]
		var sib_used: Dictionary = {}
		for ci: int in range(rcols.size()):
			var c: int = rcols[ci]
			var nid: String = "%d_%d" % [r, c]
			var forbid: Array = []
			var pars: Array = prnts.get(nid, [])
			for pid: String in pars:
				var pty: String = String((typed[pid] as Dictionary).get("type", "race"))
				if not forbid.has(pty): forbid.append(pty)
				if sib_used.has(pid):
					for st: String in (sib_used[pid] as Array):
						if not forbid.has(st): forbid.append(st)
			var is_early: bool = r < min_spec_row
			var is_pre: bool = r == (n_rows - 2)
			var cands: Array = ["race"]
			var defic: Dictionary = {}
			var specials: Array = ["errand", "bench", "rival", "parts_van", "lockup", "act_rival"]
			for t: String in specials:
				var cc: int = int(cur_count.get(t, 0))
				var tg: int = int(target.get(t, 0))
				if cc < tg:
					var allow: bool = true
					if is_early and t in ["rival", "bench", "lockup", "act_rival"]: allow = false
					if t == "bench" and is_pre: allow = false
					if allow:
						cands.append(t)
						defic[t] = float(tg - cc) / float(maxi(1, tg))
			var filtered: Array = []
			for cand in cands:
				if not forbid.has(cand):
					filtered.append(cand)
			if filtered.is_empty():
				# Variety fallback: any type this row allows that is not already
				# on the parent edge or used by a sibling. The act's hard bans
				# still apply, so early rows choose from race/errand/parts_van and
				# later rows from the full set. Siblings are bounded below the
				# pool size, so a distinct type is always found.
				var fb_list: Array = ["race", "errand", "parts_van", "rival", "bench", "lockup", "act_rival"]
				for fb in fb_list:
					if is_early and fb in ["rival", "bench", "lockup", "act_rival"]:
						continue
					if fb == "bench" and is_pre:
						continue
					if not forbid.has(fb):
						filtered = [fb]
						break
				if filtered.is_empty():
					# Unreachable with the bounded sibling counts; keep the act
					# bans intact rather than inventing an illegal type.
					if not forbid.has("race"):
						filtered = ["race"]
					else:
						# over-fanout used all allowable types (incl. race forbidden by sibs); reject so jitter can find non-collapsing spread
						return {}
			# Apply the parent-edge and sibling restrictions in the normal case
			# too; previously only the empty-filter fallback updated the pool.
			cands = filtered
			if cands.size() > 1:
				cands.sort_custom(func(aa: String, bb: String) -> bool:
					var da: float = float(defic.get(aa, 0.0))
					var db: float = float(defic.get(bb, 0.0))
					if da > db: return true
					if da < db: return false
					return aa < bb
				)
			var pu: float = _roll(map_seed, r, "pick_c%d" % c, TYPE_SALT)
			var idx: int = int(pu * float(cands.size()))
			if pu < 0.55 and cands.size() > 1 and defic.get(cands[0] if cands.size()>0 else "race", 0.0) > 0.0: idx = 0
			idx = clampi(idx, 0, cands.size() - 1)
			var chosen: String = String(cands[idx])
			if chosen == "rival" and int(cur_count.get("act_rival", 0)) < int(target.get("act_rival", 0)):
				var au: float = _roll(map_seed, r, "ar_c%d" % c, ACT_RIVAL_SALT)
				if au < 0.45 or r >= int(float(n_rows) * 0.55):
					chosen = "act_rival"
			typed[nid]["type"] = chosen
			cur_count[chosen] = int(cur_count.get(chosen, 0)) + 1
			for pid: String in pars:
				if not sib_used.has(pid): sib_used[pid] = []
				(sib_used[pid] as Array).append(chosen)
	return typed

static func generate(run_seed: int, act: int) -> RunMap:
	var rs: int = posmod(run_seed, 0x7FFFFFFF)
	var a: int = clampi(act, 1, 3)
	for j: int in range(256):
		var mseed: int = _derive_map_seed(rs, a, j)
		var built: Dictionary = _try_build(mseed, rs, a)
		if not built.is_empty():
			var rm := new()
			rm.run_seed = rs
			rm.act = a
			rm.num_rows = int(built.get("num_rows", 0))
			rm.num_paths = int(built.get("num_paths", 0))
			rm.path_count = int(built.get("path_count", 0))
			var nd: Dictionary = built.get("nodes", {}) as Dictionary
			rm.nodes = {}
			for nid: String in nd:
				var d: Dictionary = nd[nid] as Dictionary
				rm.nodes[nid] = {"id": nid, "row": int(d.get("row", 0)), "col": int(d.get("col", 0)), "type": String(d.get("type", "race"))}
			rm.parents = (built.get("parents", {}) as Dictionary).duplicate(true)
			rm.children = (built.get("children", {}) as Dictionary).duplicate(true)
			rm.row_nodes = []
			var rcs: Array = built.get("rows", [])
			for rr: int in range(rm.num_rows):
				var lst: Array[Dictionary] = []
				var cols_at: Array = (rcs[rr] if rr < rcs.size() else []) as Array
				for ccv: Variant in cols_at:
					var cc: int = int(ccv)
					var idd: String = "%d_%d" % [rr, cc]
					if rm.nodes.has(idd):
						lst.append((rm.nodes[idd] as Dictionary).duplicate(true))
				rm.row_nodes.append(lst)
			return rm
	# fallback path=1
	var spec: Dictionary = get_act_spec(a)
	var nr: int = int(spec["rows"])
	var rmf := new()
	rmf.run_seed = rs
	rmf.act = a
	rmf.num_rows = nr
	rmf.num_paths = 1
	rmf.path_count = 1
	rmf.nodes = {}
	rmf.parents = {}
	rmf.children = {}
	rmf.row_nodes = []
	var center: int = NUM_COLUMNS / 2
	for rr: int in range(nr):
		var lst: Array[Dictionary] = []
		var c: int = center
		var idd: String = "%d_%d" % [rr, c]
		var t: String = "race" if rr < nr-1 else "bench"
		if rr == 0: t = "race"
		var n: Dictionary = {"id": idd, "row": rr, "col": c, "type": t}
		rmf.nodes[idd] = n
		lst.append(n.duplicate(true))
		rmf.row_nodes.append(lst)
		if rr < nr-1:
			var pid: String = idd
			var cid: String = "%d_%d" % [rr+1, center]
			rmf.children[pid] = [cid]
			rmf.parents[cid] = [pid]
	return rmf

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
	var rm := new()
	var ver: Variant = data.get("schema_version", 0)
	if (ver is int or ver is float) and int(ver) == SCHEMA_VERSION:
		rm.run_seed = int(data.get("run_seed", 0))
		rm.act = int(data.get("act", 1))
		rm.num_rows = int(data.get("num_rows", 0))
		rm.num_paths = int(data.get("num_paths", 0))
		rm.path_count = int(data.get("path_count", 0))
		var ndin: Dictionary = data.get("nodes", {}) as Dictionary
		rm.nodes = {}
		for nid: String in ndin:
			var d: Dictionary = ndin[nid] as Dictionary
			rm.nodes[nid] = {"id": nid, "row": int(d.get("row", 0)), "col": int(d.get("col", 0)), "type": String(d.get("type", "race"))}
		rm.parents = (data.get("parents", {}) as Dictionary).duplicate(true)
		rm.children = (data.get("children", {}) as Dictionary).duplicate(true)
		rm.row_nodes = []
		for rr: int in range(rm.num_rows):
			var lst: Array[Dictionary] = []
			for nid: String in rm.nodes:
				var n: Dictionary = rm.nodes[nid]
				if int(n.get("row", -1)) == rr:
					lst.append(n.duplicate(true))
			lst.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("col", 0)) < int(y.get("col", 0)))
			rm.row_nodes.append(lst)
	return rm

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
