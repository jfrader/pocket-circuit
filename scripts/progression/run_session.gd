class_name RunSession
extends RefCounted

const SCHEMA_VERSION := 2

const FINAL_ACT := 3
const RACE_NODE_TYPES: Array[String] = ["race", "rival", "act_rival"]

const RUN_MAP := preload("res://scripts/progression/run_map.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")

const INITIAL_POINTS := 0
const RIVAL_LOSS_POINTS_COST := 10
const ERRAND_PAY_POINTS := 6
const VAN_PART_COSTS := {"tool_kit": 5, "tyre_set": 10, "spare_shell": 15}
const RIVAL_LOSS_SEVERITY := 0.6
const LOCKUP_CAR_TYPE := "compact"
const STARTER_CAR := "rustbug"
const STARTER_CAR_TYPE := "compact"
const CAR_ORIGIN_START := "start"
const CAR_ORIGIN_RIVAL := "rival"
const CAR_ORIGIN_LOCKUP := "lockup"

const RUN_POINTS_BY_FINISH: Dictionary = {
	1: 6,
	2: 4,
	3: 2,
	4: 0,
}

## Run session layer: pure logic over the run map + run state. No UI, no
## scenes, no Node dependencies. Deterministic from run_seed.
##
## Points are the run's only currency: races pay RUN_POINTS_BY_FINISH, the
## parts van and a lost rival duel spend them.
##
## create(run_seed): act 1 map, on the opening race, 0 points, rustbug clean.
## available_nodes() / enter_node(id): moves along map edges only, and never
##   past a race-type node that has not been raced.
##
## Resolution (the node must be current, unresolved and of the right type):
##   resolve_race(id, pos, field): pays points. On the act rival, a win
##     advances the act (act 3 completes the run) and any other finish fails it.
##   resolve_rival(id, won): a win adds the rival's car (won_cars()); a loss costs
##     RIVAL_LOSS_POINTS_COST, and wear when the points do not cover it.
##   bench_repair(car) / bench_fit(car, part): one of the two per bench visit.
##   spend(cost): parts van purchase from points.
##   open_lockup(): the act's one free car.
##   resolve_errand(choice): 0 takes ERRAND_PAY_POINTS, 1 steps the current
##     car's wear back one level.
##
## register_crash(severity) advances wear; worn out fails the run.
## serialize()/deserialize() round-trip the whole session; a schema mismatch
## or an unreadable inner block deserializes to null.

var run_seed: int = 0
var run_state: RunState
var current_map: RunMap
var current_node_id: String = ""
var run_points: int = 0
var current_car_id: String = STARTER_CAR
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
	sess.current_car_id = STARTER_CAR
	sess.owned_cars = {}
	sess.lockup_used = false
	sess.failed = false
	sess.completed = false
	sess.installed_parts = {}
	sess.last_bench_visited = ""
	sess.bench_action_done = false
	sess.owned_cars[STARTER_CAR] = {"type": STARTER_CAR_TYPE, "won_from": CAR_ORIGIN_START}
	sess.run_state.get_or_create_car_roll(STARTER_CAR, STARTER_CAR_TYPE)
	sess.run_state.set_car_wear(STARTER_CAR, RUN_STATE.WEAR_LEVELS[0])
	sess.run_state.act = 1
	sess.run_state.row = 0
	return sess

## The stops the player can take next: the current node while it is an
## unraced race, otherwise its children.
func available_nodes() -> Array[Dictionary]:
	if current_map == null or current_node_id.is_empty() or failed or completed:
		return []
	if is_race_pending():
		return [current_node()]
	return current_map.get_children(current_node_id)

## A race-type node has to be raced before the run moves past it.
func is_race_pending() -> bool:
	return String(current_node().get("type", "")) in RACE_NODE_TYPES and not resolved_nodes.has(current_node_id)

func current_node() -> Dictionary:
	if current_map == null or current_node_id.is_empty():
		return {}
	return current_map.get_node(current_node_id)

func enter_node(node_id: String) -> bool:
	if failed or completed or current_map == null or current_node_id.is_empty():
		return false
	if is_race_pending():
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
			if current_map.act < FINAL_ACT:
				_advance_to_act(current_map.act + 1)
				outcome["act_advanced"] = true
			else:
				completed = true
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
		outcome["car"] = _win_car(node_id, CAR_ORIGIN_RIVAL, "")
	else:
		var over: bool = run_points < RIVAL_LOSS_POINTS_COST
		run_points = maxi(0, run_points - RIVAL_LOSS_POINTS_COST)
		outcome["cost"] = RIVAL_LOSS_POINTS_COST
		outcome["wear_advanced"] = over
		if over:
			register_crash(RIVAL_LOSS_SEVERITY)
	return outcome

func _is_current_node_type(nt: String) -> bool:
	if current_node_id.is_empty():
		return false
	var n: Dictionary = current_node()
	return String(n.get("type", "")) == nt

## Adds a car won at this stop: a unique id, a seed for its look, a type
## (rolled for rivals, fixed for lockups) and its run roll.
func _win_car(stop_id: String, origin: String, fixed_type: String) -> Dictionary:
	var vid := "car-%d-a%d-%s" % [run_seed, current_map.act, stop_id]
	var car_seed := vid.hash() & 0x7FFFFFFF
	var types := ProceduralCarGenerator.SUPPORTED_TYPES
	var car_type := fixed_type if not fixed_type.is_empty() else types[car_seed % types.size()]
	owned_cars[vid] = {"type": car_type, "seed": car_seed, "won_from": origin, "act": current_map.act}
	run_state.get_or_create_car_roll(vid, car_type)
	return won_car(vid)


## A won car as the garage stores it: {id, seed, type, roll, won_from, act}.
func won_car(vehicle_id: String) -> Dictionary:
	var record: Dictionary = owned_cars.get(vehicle_id, {})
	if String(record.get("won_from", "")) == CAR_ORIGIN_START:
		return {}
	var out := record.duplicate(true)
	out["id"] = vehicle_id
	out["roll"] = run_state.get_or_create_car_roll(vehicle_id, String(record["type"]))
	return out


## A stored won car with every field checked, or {} when it cannot be trusted.
static func normalize_won_car(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var car := value as Dictionary
	var car_id: Variant = car.get("id")
	var car_type: Variant = car.get("type")
	var origin: Variant = car.get("won_from")
	var roll: Variant = car.get("roll")
	if car_id is not String or String(car_id).is_empty() or car_type not in ProceduralCarGenerator.SUPPORTED_TYPES:
		return {}
	if origin not in [CAR_ORIGIN_RIVAL, CAR_ORIGIN_LOCKUP] or roll is not Dictionary:
		return {}
	var limit: float = RUN_STATE.TIER_ENVELOPES.values().max()
	var clean_roll := {}
	for axis: String in CarProfile.AXES:
		var amount: Variant = (roll as Dictionary).get(axis)
		if not (amount is float or amount is int):
			return {}
		clean_roll[axis] = clampf(float(amount), -limit, limit)
	return {
		"id": String(car_id),
		"seed": maxi(0, int(car.get("seed", 0))),
		"type": String(car_type),
		"roll": clean_roll,
		"won_from": String(origin),
		"act": clampi(int(car.get("act", 1)), 1, FINAL_ACT),
	}


## Every car won this run, in the order they were won.
func won_cars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for vehicle_id: String in owned_cars:
		var car := won_car(vehicle_id)
		if not car.is_empty():
			out.append(car)
	return out

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
	return true

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
	if run_points >= cost:
		run_points -= cost
		resolved_nodes[current_node_id] = true
		return true
	return false

func open_lockup() -> Dictionary:
	if failed or completed or lockup_used:
		return {}
	if resolved_nodes.has(current_node_id):
		return {}
	resolved_nodes[current_node_id] = true
	lockup_used = true
	return _win_car("lockup", CAR_ORIGIN_LOCKUP, LOCKUP_CAR_TYPE)

func resolve_errand(choice: int) -> Dictionary:
	if not _is_current_node_type("errand"):
		return {"error": "not current errand node"}
	if resolved_nodes.has(current_node_id):
		return {"error": "already resolved"}
	resolved_nodes[current_node_id] = true
	var eff: String = ""
	var amt: int = 0
	if choice == 0:
		run_points += ERRAND_PAY_POINTS
		eff = "points"
		amt = ERRAND_PAY_POINTS
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
		sess.run_state = RUN_STATE.deserialize(data.get("run_state", {}) as Dictionary)
		sess.current_map = RUN_MAP.deserialize(data.get("current_map", {}) as Dictionary)
		if sess.run_state == null or sess.current_map == null:
			return null
		sess.current_node_id = String(data.get("current_node_id", ""))
		sess.run_points = int(data.get("run_points", 0))
		sess.current_car_id = String(data.get("current_car_id", STARTER_CAR))
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
	return "RunSession(seed=%d, act=%d, node=%s, pts=%d, failed=%s, complete=%s)" % [
		run_seed, actv, current_node_id, run_points, str(failed), str(completed)
	]
