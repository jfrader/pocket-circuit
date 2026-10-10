extends SceneTree

## GURI-1821 (Parts van purchases change nothing on the car): every part moves
## the car's physics both ways, the van stocks rolled parts, a bench fits one to
## the car being driven, the race builds that car with it, and the garage copy
## of a won car carries no parts.

const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_STATE := preload("res://scripts/progression/run_state.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for check: Callable in [_check_parts, _check_deal, _check_session]:
		check.call()
		if _failed:
			return
	await _check_screens()
	if _failed:
		return
	print("RUN_PARTS_TEST PASS")
	quit(0)


## Every upside and every downside it can carry moves each listed stat its way,
## and a pile of parts never leaves a range.
func _check_parts() -> void:
	var base := CATALOG.create_vehicle_stats("rustbug")
	for part_id: String in RunParts.UPSIDES:
		var allowed := RunParts.downsides_for(part_id)
		if not _expect(not allowed.is_empty(), "%s can carry a downside" % part_id):
			return
		for downside_id: String in allowed:
			var part := {"part": part_id, "downside": downside_id}
			var fitted := RunParts.apply(base, [part])
			for side: Dictionary in [RunParts.UPSIDES[part_id], RunParts.DOWNSIDES[downside_id]]:
				var moves: Dictionary = side["moves"]
				for field: String in moves:
					var moved := float(fitted.get(field)) - float(base.get(field))
					if not _expect(signf(moved) == signf(float(moves[field])), "%s / %s moves %s its way" % [part_id, downside_id, field]):
						return
	var pile: Array = []
	for part_id: String in RunParts.UPSIDES:
		for downside_id: String in RunParts.downsides_for(part_id):
			pile.append({"part": part_id, "downside": downside_id})
	var stacked := RunParts.apply(base, pile + pile)
	if not _expect(stacked.get_validation_errors().is_empty(), "every part twice over stays inside every range: %s" % str(stacked.get_validation_errors())):
		return
	if not _expect(RunParts.normalize({"part": "long_gears", "downside": "top_speed"}).is_empty() and RunParts.normalize({"part": "rocket", "downside": "heavy"}).is_empty(), "a downside on its upside's stats, or an unknown part, is not a part"):
		return


## A van's stock comes from its roll and the car it sells to: the same stop
## deals the same parts, each distinct with an allowed downside and an upside
## that changes that car; every car type, rolled to either extreme, still fills
## a van, and the vans reach every part.
func _check_deal() -> void:
	var seen := {}
	var limit: float = RUN_STATE.TIER_ENVELOPES.values().max()
	for car_type: String in ProceduralCarGenerator.SUPPORTED_TYPES:
		var base := CATALOG.create_vehicle_stats(String(CATALOG.base_vehicle_for_type(car_type)["id"]))
		for sign: float in [0.0, 1.0, -1.0]:
			var roll := {}
			for axis: String in CarProfile.AXES:
				roll[axis] = sign * limit
			var car := CarProfile.apply_roll(base, roll)
			for stop_roll: int in 60:
				var stock := RunParts.deal(stop_roll, car)
				if not _expect(stock == RunParts.deal(stop_roll, car) and stock.size() == RunParts.VAN_STOCK, "a %s van roll deals the same %d parts" % [car_type, RunParts.VAN_STOCK]):
					return
				var ids := {}
				for part: Dictionary in stock:
					ids[part["part"]] = true
					seen[part["part"]] = true
					if not _expect(String(part["downside"]) in RunParts.downsides_for(String(part["part"])), "a dealt downside is allowed for its part"):
						return
					if not _expect(RunParts.upside_gain(car, String(part["part"])) >= RunParts.MIN_UPSIDE_GAIN, "a %s van never sells %s, which would barely change it" % [car_type, part["part"]]):
						return
				if not _expect(ids.size() == stock.size(), "a van stocks distinct parts"):
					return
	if not _expect(seen.size() == RunParts.UPSIDES.size(), "the vans reach every part"):
		return


## Bought parts are held, a fit puts one on the current car only, the car's
## record carries it while its garage copy does not, and the save keeps both.
func _check_session() -> void:
	var sess = RUN_SESSION.create(5150)
	var starter: String = sess.current_car_id
	var part: Dictionary = RunParts.deal(9, sess.car_stats(starter))[0]
	sess.parts_held.append(part)
	sess.current_node_id = "test_bench"
	sess.current_map.nodes["test_bench"] = {"id": "test_bench", "type": "bench"}
	sess.last_bench_visited = "test_bench"
	if not _expect(not sess.bench_fit(starter, 1) and sess.bench_fit(starter, 0), "a bench fits a held part by its place in the pile"):
		return
	if not _expect(sess.parts_held.is_empty() and sess.fitted_parts(starter) == [part] and sess.car_record(starter)["fitted_parts"] == [part], "the fitted part leaves the pile and rides on the car"):
		return
	var won_id: String = sess._add_car("test", RUN_SESSION.CAR_ORIGIN_RIVAL, ProceduralCarGenerator.SUPPORTED_TYPES)
	sess.installed_parts[won_id] = [part]
	if not _expect(not sess.won_car(won_id).has("fitted_parts") and sess.car_record(won_id)["fitted_parts"] == [part], "a won car goes to the garage without its parts"):
		return
	var data: Dictionary = RUN_SESSION.serialize(sess)
	data["installed_parts"]["ghost-car"] = [part]
	data["installed_parts"][won_id] = [part, {"part": "rocket", "downside": "heavy"}, "spare"]
	data["parts_held"] = [part, "tool_kit"]
	var loaded = RUN_SESSION.deserialize(data)
	if not _expect(loaded != null and loaded.fitted_parts(starter) == [part] and loaded.fitted_parts(won_id) == [part], "a reloaded night keeps each car's parts"):
		return
	if not _expect(loaded.parts_held == [part] and not loaded.installed_parts.has("ghost-car"), "stored parts that cannot be trusted are dropped"):
		return
	var plain := CATALOG.create_vehicle_stats(starter)
	VehicleDirectory.install([CATALOG.generated_vehicle(sess.car_record(starter))])
	var fitted := CATALOG.create_vehicle_stats(starter)
	var expected := RunParts.apply(CarProfile.apply_roll(CATALOG.create_vehicle_stats(String(CATALOG.base_vehicle_for_type(String(sess.car_record(starter)["type"]))["id"])), sess.car_record(starter)["roll"]), [part])
	VehicleDirectory.clear()
	for field: String in VehicleStats.PARAMETER_RANGES:
		if not _expect(is_equal_approx(float(fitted.get(field)), float(expected.get(field))), "the catalog builds a fitted car as its roll then its parts (%s)" % field):
			return
	if not _expect(plain != null, "the catalog builds a car with no parts"):
		return


## The van shows each part with what it gives and takes and sells it; the bench
## fits it; the next race builds the car with it.
func _check_screens() -> void:
	var app := root.get_node_or_null("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var sess: RunSession = app.call("start_run", 4401) as RunSession
	if not _expect(sess != null and RUN_WALK.walk_to(app, sess, "parts_van"), "a parts van is reachable"):
		return
	sess.run_points = 30
	var stock := sess.van_stock()
	shell.call("show_run_parts_van")
	for frame in 4:
		await process_frame
	for part: Dictionary in stock:
		var buy := shell.find_child("VanBuy_" + String(part["part"]), true, false) as Button
		if not _expect(buy != null and not buy.disabled and _has_label(buy, "%s · %d POINTS" % [RunParts.part_name(part).to_upper(), RunParts.cost(part)]), "the van lists %s with its price" % part["part"]):
			return
		if not _expect(_has_label(shell, "+ " + RunParts.upside_copy(part)) and _has_label(shell, "− " + RunParts.downside_copy(part)), "the van prints what %s gives and takes" % part["part"]):
			return
	if not _expect(_fits(shell, "VanParts"), "the van keeps its parts and legend inside the viewport"):
		return
	if not _expect(root.gui_get_focus_owner() == shell.find_child("VanBuy_" + String(stock[0]["part"]), true, false), "the van opens on its first part"):
		return
	(shell.find_child("VanBuy_" + String(stock[0]["part"]), true, false) as Button).pressed.emit()
	await process_frame
	if not _expect(sess.parts_held == [stock[0]] and sess.run_points == 30 - RunParts.cost(stock[0]), "buying holds the part and spends its price"):
		return
	var saved: Dictionary = SAVE_STORE.new(String(app.get("_save_store").get("save_path"))).load_data()
	if not _expect(((saved.get("current_run", {}) as Dictionary).get("parts_held", []) as Array).size() == 1, "the save holds the bought part"):
		return

	if not _expect(RUN_WALK.walk_to(app, sess, "bench"), "a bench is reachable after the van"):
		return
	var car: String = sess.current_car_id
	var before := CATALOG.create_vehicle_stats(car)
	sess.parts_held.append(stock[1])
	shell.call("show_run_bench")
	for frame in 4:
		await process_frame
	var fit := shell.find_child("BenchFit_0", true, false) as Button
	if not _expect(fit != null and not fit.disabled and _has_label(shell, "− " + RunParts.downside_copy(stock[0])), "the bench offers the held part with its downside"):
		return
	if not _expect(_fits(shell, "BenchParts"), "the bench keeps its parts and legend inside the viewport"):
		return
	fit.pressed.emit()
	await process_frame
	if not _expect(sess.fitted_parts(car) == [stock[0]] and sess.parts_held == [stock[1]] and sess.bench_action_done, "fitting uses the bench visit and puts the part on the car"):
		return
	var after := CATALOG.create_vehicle_stats(car)
	var expected := RunParts.apply(before, [stock[0]])
	for field: String in VehicleStats.PARAMETER_RANGES:
		if not _expect(is_equal_approx(float(after.get(field)), float(expected.get(field))), "the car the race builds has the part's handling (%s)" % field):
			return
	if not _expect(RunParts.upside_gain(before, String(stock[0]["part"])) >= RunParts.MIN_UPSIDE_GAIN, "the fitted part changes the car"):
		return
	shell.call("show_run_bench")
	await process_frame
	var left := shell.find_child("BenchFit_0", true, false) as Button
	if not _expect((shell.find_child("BenchRepair", true, false) as Button).disabled and left != null and left.disabled, "a used bench offers nothing more"):
		return
	app.call("abandon_run")


func _fits(shell: Node, card_name: String) -> bool:
	var legend := shell.find_child("RunLegend", true, false) as Control
	var back := shell.find_child("ActionBack", true, false) as Control
	var card := shell.find_child(card_name, true, false) as Control
	if legend == null or back == null or card == null:
		return false
	var top := legend.get_global_rect().position.y
	return legend.get_global_rect().end.y <= root.get_visible_rect().end.y and back.get_global_rect().end.y < top and card.get_global_rect().end.y < top


func _has_label(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text) == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_PARTS_TEST FAIL: " + message)
	quit(1)
	return false
