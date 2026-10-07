class_name RunSession
extends RefCounted

const SCHEMA_VERSION := 1

const RUN_MAP := preload("res://scripts/progression/run_map.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")

const INITIAL_BUDGET := 60
const INITIAL_POINTS := 0
const RIVAL_LOSS_BUDGET_COST := 15
const RIVAL_LOSS_SEVERITY := 0.6
const LOCKUP_CAR_TYPE := "compact"

const RUN_POINTS_BY_FINISH: Dictionary = {
	1: 6,
	2: 4,
	3: 2,
	4: 0,
}

## Run session layer (GURI-1740 first slice): pure logic over the run map + run state.
## No UI, no scenes, no Node dependencies. All deterministic from run_seed.
##
## Creation:
##   create(run_seed) -> act 1 map, positioned on start node (race), budget=60, points=0,
##   initial car "rustbug" (compact) owned+current with roll+clean wear.
##
## Navigation (map edges strictly enforced):
##   available_nodes() -> Array[Dictionary] (children of current)
##   current_node() -> Dictionary
##   enter_node(id: String) -> bool
##   On enter bench: reset per-visit action flag.
##   On resolving the final bench (last row): act<3 advances to next act via map regen, act==3 sets completed.
##   Use bench_continue() to advance final bench without requiring a repair/fit action this visit.
##
## Per-type resolution (game layer calls with real outcomes after node "play"):
##   All require node_id matches current and type matches, else refuse (return error or false).
##
##   resolve_race(node_id, finish_position: int, field_size: int) -> Dictionary
##     Awards from RUN_POINTS_BY_FINISH (pos clamped 1..field).
##     qualified = (pos <= maxi(1, field_size/2 + 1))
##     If type=="act_rival":
##       pos==1 and act<3: advance act (regenerate map from same seed, reset to start of next, lockup=false)
##       pos>1: failed=true (loss on act rival ends the run)
##     Returns: {points_gained:int, qualified:bool, act_advanced:bool, run_failed:bool}
##
##   resolve_rival(node_id, won: bool) -> Dictionary
##     If won: fabricate vid="rival_"+node_id, type=_rival_type_for_act(act) e.g. "coupe",
##             get_or_create roll via run_state, add to owned_cars, return car info.
##     If lost: budget = max(0, budget-15); if cost exceeded available then also register_crash(0.6)
##     Returns: for win {car: {vehicle_id,car_type,roll}}, for loss {cost, wear_advanced:bool}
##
##   bench_repair(car_key: String) -> bool
##   bench_fit(car_key: String, part: String) -> bool
##     ONLY on current "bench" node visit, and only ONE of the two per visit.
##     After first action on this bench node, the other (and repeat) refused (return false).
##     repair: if car_key owned or current, run_state.set wear = restore_at_bench (clean)
##     fit: installed_parts[car_key] = part (effect out of scope for this layer)
##     Documented rule: bench is mutually exclusive repair-OR-fit; layer makes calling both impossible.
##
##   bench_continue() -> bool
##     Allowed on any current bench node (final or not). Does not count against the repair/fit action.
##     If the bench is the final row of act<3: performs the act advance (regens map, resets flags).
##     If final of act 3: sets completed.
##
##   spend(cost: int) -> bool   # for parts_van node
##     deducts from run_budget if affordable, else false. No negative budget.
##
##   open_lockup() -> Dictionary
##     If !lockup_used (scarce, once per act): vid="lockup_act%d"%act , type=compact,
##     add to owned, mark used, return {vehicle_id,car_type,roll}
##     Subsequent calls in act return {}
##
##   resolve_errand(choice: int) -> Dictionary
##     Documented minimal outcome table:
##       0: +12 budget ("quick gig")
##       1: +3 points ("tip off")
##       else: step back one wear level on current car if not clean ("tune up")
##     Returns {effect: "budget"|"points"|"restore", amount: int}
##
## Attrition:
##   register_crash(severity: float)
##     run_state.advance_wear on CURRENT car; if reaches "dented" then failed=true
##     Bench repair is ONLY way to restore (via restore_at_bench).
##   is_failed() -> bool  (also true if current wear is worn_out)
##
## Run end:
##   is_complete() -> bool  (resolved the final bench of act 3 without having failed)
##   serialize() / deserialize() roundtrips full session (map+state+position+budgets+owned+flags)
##
## Ownership:
##   Starts with rustbug. Rival wins and lockups add more (with rolls in run_state).
##   Bench/repairs/fits apply to any owned or current car_key.
##
## Determinism: same seed + same enter/resolve sequence + same outcome args => identical state.

var run_seed: int = 0
var run_state: RunState
var current_map: RunMap
var current_node_id: String = ""
var run_points: int = 0
var run_budget: int = 0
var current_car_id: String = "rustbug"
var owned_cars: Dictionary = {}
var lockup_used: bool = false
var failed: bool = false
var completed: bool = false
var installed_parts: Dictionary = {}
var last_bench_visited: String = ""
var bench_action_done: bool = false
var resolved_nodes: Dictionary = {}

static func create(p_run_seed: int) -> RunSession:
	var sess: RunSession = new()
	sess.run_seed = posmod(p_run_seed, 0x7FFFFFFF)
	sess.run_state = RUN_STATE.create(sess.run_seed)
	sess.current_map = RUN_MAP.generate(sess.run_seed, 1)
	var start_n: Dictionary = sess.current_map.get_start_node()
	sess.current_node_id = String(start_n.get("id", ""))
	sess.run_points = INITIAL_POINTS
	sess.run_budget = INITIAL_BUDGET
	sess.current_car_id = "rustbug"
	sess.owned_cars = {}
	sess.lockup_used = false
	sess.failed = false
	sess.completed = false
	sess.installed_parts = {}
	sess.last_bench_visited = ""
	sess.bench_action_done = false
	var init_type: String = "compact"
	sess.owned_cars["rustbug"] = init_type
	sess.run_state.get_or_create_car_roll("rustbug", init_type)
	sess.run_state.set_car_wear("rustbug", "clean")
	sess.run_state.act = 1
	sess.run_state.row = 0
	return sess

func available_nodes() -> Array[Dictionary]:
	if current_map == null or current_node_id.is_empty():
		return []
	return current_map.get_children(current_node_id)

func current_node() -> Dictionary:
	if current_map == null or current_node_id.is_empty():
		return {}
	return current_map.get_node(current_node_id)

func enter_node(node_id: String) -> bool:
	if failed or completed or current_map == null or current_node_id.is_empty():
		return false
	var kids: Array[Dictionary] = current_map.get_children(current_node_id)
	var is_valid: bool = false
	for k: Dictionary in kids:
		if String(k.get("id", "")) == node_id:
			is_valid = true
			break
	if not is_valid:
		return false
	current_node_id = node_id
	var n: Dictionary = current_map.get_node(node_id)
	var r: int = int(n.get("row", 0))
	run_state.row = r
	var ntype: String = String(n.get("type", "race"))
	if ntype == "bench":
		last_bench_visited = node_id
		bench_action_done = false
	return true

func resolve_race(node_id: String, finish_position: int, field_size: int) -> Dictionary:
	if not _is_current_node_type_for_race(node_id):
		return {"error": "not current race or act_rival node"}
	if resolved_nodes.has(node_id):
		return {"error": "already resolved"}
	resolved_nodes[node_id] = true
	var n: Dictionary = current_node()
	var ntype: String = String(n.get("type", ""))
	var pos: int = clampi(finish_position, 1, maxi(field_size, 1))
	var pts: int = int(RUN_POINTS_BY_FINISH.get(pos, 0))
	run_points += pts
	var half: int = maxi(1, field_size / 2 + 1)
	var qualified: bool = pos <= half
	var outcome: Dictionary = {
		"points_gained": pts,
		"qualified": qualified,
		"act_advanced": false,
		"run_failed": false,
	}
	if ntype == "act_rival":
		if pos == 1:
			var next_act: int = current_map.act + 1
			if next_act <= 3:
				_advance_to_act(next_act)
				outcome["act_advanced"] = true
			# for act 3 rival win: stay in act 3, must still reach final bench node to complete run
		else:
			failed = true
			outcome["run_failed"] = true
	return outcome

func _is_current_node_type_for_race(node_id: String) -> bool:
	if current_node_id != node_id:
		return false
	var n: Dictionary = current_node()
	var t: String = String(n.get("type", ""))
	return t == "race" or t == "act_rival"

func _advance_to_act(new_act: int) -> void:
	if new_act < 1 or new_act > 3:
		return
	current_map = RUN_MAP.generate(run_seed, new_act)
	var start_n: Dictionary = current_map.get_start_node()
	current_node_id = String(start_n.get("id", ""))
	lockup_used = false
	bench_action_done = false
	last_bench_visited = ""
	resolved_nodes.clear()
	run_state.act = new_act
	run_state.row = 0

func resolve_rival(node_id: String, won: bool) -> Dictionary:
	if not (current_node_id == node_id and _is_current_node_type("rival")):
		return {"error": "not current rival node"}
	if resolved_nodes.has(node_id):
		return {"error": "already resolved"}
	resolved_nodes[node_id] = true
	var outcome: Dictionary = {"won": won}
	if won:
		var vid: String = "rival_" + node_id
		var atype: String = _rival_type_for_act(current_map.act)
		owned_cars[vid] = atype
		var roll: Dictionary = run_state.get_or_create_car_roll(vid, atype)
		outcome["car"] = {
			"vehicle_id": vid,
			"car_type": atype,
			"roll": roll.duplicate(true),
		}
	else:
		var pre_budget: int = run_budget
		run_budget = maxi(0, run_budget - RIVAL_LOSS_BUDGET_COST)
		var over: bool = pre_budget < RIVAL_LOSS_BUDGET_COST
		outcome["cost"] = RIVAL_LOSS_BUDGET_COST
		outcome["wear_advanced"] = over
		if over:
			register_crash(RIVAL_LOSS_SEVERITY)
	return outcome

func _is_current_node_type(nt: String) -> bool:
	if current_node_id.is_empty():
		return false
	var n: Dictionary = current_node()
	return String(n.get("type", "")) == nt

func _rival_type_for_act(a: int) -> String:
	if a <= 1:
		return "coupe"
	if a == 2:
		return "muscle"
	return "suv"

func bench_repair(car_key: String) -> bool:
	var can: bool = _can_do_bench_action(car_key)
	if not can:
		return false
	var hask: bool = owned_cars.has(car_key)
	var iscurk: bool = (car_key == current_car_id)
	if not hask and not iscurk:
		return false
	var cur_w: String = run_state.get_car_wear(car_key)
	var restored: String = RUN_STATE.restore_at_bench(cur_w)
	run_state.set_car_wear(car_key, restored)
	bench_action_done = true
	_maybe_complete_on_final_bench()
	return true

func bench_fit(car_key: String, part: String) -> bool:
	if not _can_do_bench_action(car_key):
		return false
	if not owned_cars.has(car_key) and car_key != current_car_id:
		return false
	if part.is_empty():
		return false
	installed_parts[car_key] = part
	bench_action_done = true
	_maybe_complete_on_final_bench()
	return true

func bench_continue() -> bool:
	if failed or completed:
		return false
	if not _is_current_node_type("bench"):
		return false
	# explicit continue path so final bench can advance act without repair/fit being possible or wanted.
	# repair XOR fit per visit remains enforced by _can_do + bench_action_done.
	_maybe_complete_on_final_bench()
	return true

## Resolving the forced final bench (last row, always bench type) ends the current act:
## - act < 3: _advance_to_act (regens map from same seed, resets to start of next act, lockup_used=false)
## - act == 3: set completed=true
## Invoked after bench action or via bench_continue.
func _maybe_complete_on_final_bench() -> void:
	if current_map == null:
		return
	if not current_map.is_last_row(int(run_state.row)):
		return
	if current_map.act == 3:
		completed = true
	else:
		_advance_to_act(current_map.act + 1)


func _can_do_bench_action(_car_key: String) -> bool:
	if failed or completed:
		return false
	if not _is_current_node_type("bench"):
		return false
	if last_bench_visited != current_node_id or bench_action_done:
		return false
	return true

func spend(cost: int) -> bool:
	if failed or completed or cost <= 0:
		return false
	if resolved_nodes.has(current_node_id):
		return false
	if run_budget >= cost:
		run_budget -= cost
		resolved_nodes[current_node_id] = true
		return true
	return false

func open_lockup() -> Dictionary:
	if failed or completed or lockup_used:
		return {}
	if resolved_nodes.has(current_node_id):
		return {}
	resolved_nodes[current_node_id] = true
	var vid: String = "lockup_act%d" % current_map.act
	var ctype: String = LOCKUP_CAR_TYPE
	owned_cars[vid] = ctype
	var roll: Dictionary = run_state.get_or_create_car_roll(vid, ctype)
	lockup_used = true
	return {
		"vehicle_id": vid,
		"car_type": ctype,
		"roll": roll.duplicate(true),
	}

func resolve_errand(choice: int) -> Dictionary:
	if not _is_current_node_type("errand"):
		return {"error": "not current errand node"}
	if resolved_nodes.has(current_node_id):
		return {"error": "already resolved"}
	resolved_nodes[current_node_id] = true
	var eff: String = ""
	var amt: int = 0
	if choice == 0:
		run_budget += 12
		eff = "budget"
		amt = 12
	elif choice == 1:
		run_points += 3
		eff = "points"
		amt = 3
	else:
		var cw: String = run_state.get_car_wear(current_car_id)
		var prev: String = _previous_wear_level(cw)
		if prev != cw:
			run_state.set_car_wear(current_car_id, prev)
			amt = 1
		eff = "restore"
	return {"effect": eff, "amount": amt}

func _previous_wear_level(w: String) -> String:
	var idx: int = RUN_STATE.WEAR_LEVELS.find(w)
	if idx > 0:
		return RUN_STATE.WEAR_LEVELS[idx - 1]
	return w

func register_crash(severity: float) -> void:
	if failed or completed or current_car_id.is_empty():
		return
	var cw: String = run_state.get_car_wear(current_car_id)
	var nw: String = RUN_STATE.advance_wear(cw, severity)
	run_state.set_car_wear(current_car_id, nw)
	if RUN_STATE.is_worn_out(nw):
		failed = true

func is_failed() -> bool:
	if failed:
		return true
	if current_car_id.is_empty():
		return false
	return RUN_STATE.is_worn_out(run_state.get_car_wear(current_car_id))

func is_complete() -> bool:
	return completed and not failed

static func serialize(sess: RunSession) -> Dictionary:
	if sess == null:
		return {}
	var state_snap: Dictionary = RUN_STATE.serialize(sess.run_state)
	var map_snap: Dictionary = RUN_MAP.serialize(sess.current_map)
	var own: Dictionary = sess.owned_cars.duplicate(true)
	var inst: Dictionary = sess.installed_parts.duplicate(true)
	return {
		"schema_version": SCHEMA_VERSION,
		"run_seed": sess.run_seed,
		"run_state": state_snap,
		"current_map": map_snap,
		"current_node_id": sess.current_node_id,
		"run_points": sess.run_points,
		"run_budget": sess.run_budget,
		"current_car_id": sess.current_car_id,
		"owned_cars": own,
		"lockup_used": sess.lockup_used,
		"failed": sess.failed,
		"completed": sess.completed,
		"installed_parts": inst,
		"last_bench_visited": sess.last_bench_visited,
		"bench_action_done": sess.bench_action_done,
		"resolved_nodes": sess.resolved_nodes.duplicate(true),
	}

static func deserialize(data: Dictionary) -> RunSession:
	var sess: RunSession = new()
	var ver: Variant = data.get("schema_version", 0)
	if (ver is int or ver is float) and int(ver) == SCHEMA_VERSION:
		sess.run_seed = int(data.get("run_seed", 0))
		var st_d: Dictionary = data.get("run_state", {}) as Dictionary
		sess.run_state = RUN_STATE.deserialize(st_d)
		var mp_d: Dictionary = data.get("current_map", {}) as Dictionary
		sess.current_map = RUN_MAP.deserialize(mp_d)
		sess.current_node_id = String(data.get("current_node_id", ""))
		sess.run_points = int(data.get("run_points", 0))
		sess.run_budget = int(data.get("run_budget", 0))
		sess.current_car_id = String(data.get("current_car_id", "rustbug"))
		sess.owned_cars = (data.get("owned_cars", {}) as Dictionary).duplicate(true)
		sess.lockup_used = bool(data.get("lockup_used", false))
		sess.failed = bool(data.get("failed", false))
		sess.completed = bool(data.get("completed", false))
		sess.installed_parts = (data.get("installed_parts", {}) as Dictionary).duplicate(true)
		sess.last_bench_visited = String(data.get("last_bench_visited", ""))
		sess.bench_action_done = bool(data.get("bench_action_done", false))
		sess.resolved_nodes = (data.get("resolved_nodes", {}) as Dictionary).duplicate(true)
	else:
		return null
	return sess

func _to_string() -> String:
	var actv: int = 0
	if current_map != null:
		actv = current_map.act
	return "RunSession(seed=%d, act=%d, node=%s, pts=%d, budget=%d, failed=%s, complete=%s)" % [
		run_seed, actv, current_node_id, run_points, run_budget, str(failed), str(completed)
	]
