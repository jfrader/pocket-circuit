extends SceneTree

const UI := preload("res://scripts/ui/run_ui.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
var _failed := false

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var tune_rewards := {}
	for seed_value: int in range(48):
		var session := RunSession.create(seed_value)
		for act: int in RunMap.ACT_SPECS:
			var map := RunMap.generate(seed_value, act)
			if not _expect(map != null, "map builds"):
				return
			var vans := 0
			for row: int in range(1, map.num_rows - 1):
				if not _expect(map.get_nodes_in_row(row).size() >= 2, "non-boss rows keep a choice seed %d act %d row %d" % [seed_value, act, row]):
					return
			for node: Dictionary in map.nodes.values():
				var sibling_types := {}
				for child: Dictionary in map.get_children(node["id"]):
					if not _expect(not sibling_types.has(child["type"]), "siblings offer distinct stop types seed %d act %d parent %s" % [seed_value, act, node["id"]]):
						return
					sibling_types[child["type"]] = true
				if node["type"] == "parts_van":
					vans += 1
					if not _expect(node["row"] > 0 and node["row"] < map.num_rows - 2, "van follows opening earnings and precedes final bench/rival"):
						return
				if node["row"] >= map.num_rows - 3:
					continue
				# A single-child node must not leave an unused legal fork.
				if map.get_children(node["id"]).size() < 2:
					for candidate: Dictionary in map.get_nodes_in_row(node["row"] + 1):
						if absi(candidate["col"] - node["col"]) > 1 or map.children[node["id"]].has(candidate["id"]):
							continue
						var crosses := false
						for peer: Dictionary in map.get_nodes_in_row(node["row"]):
							for child: Dictionary in map.get_children(peer["id"]):
								crosses = crosses or (node["col"] - peer["col"]) * (candidate["col"] - child["col"]) < 0
						if not _expect(crosses, "all geometrically legal forks are linked"):
							return
			if not _expect(vans >= 1, "every act offers downstream spending"):
				return
			if not _expect(RunMap.deserialize(RunMap.serialize(map)) != null, "forked map roundtrips"):
				return
		for node: Dictionary in session.current_map.nodes.values():
			if node["type"] == "parts_van":
				session.resolve_race(session.current_node_id, 1, 6)
				session.current_node_id = node["id"]
				var cheapest := 1000
				for offer: Dictionary in session.van_offer_consumables():
					cheapest = mini(cheapest, offer["price"])
				if not _expect(cheapest <= session.run_points and session.buy_nitro(), "one P1 buys a listed consumable"):
					return
				break
		for node: Dictionary in session.current_map.nodes.values():
			if node["type"] == "errand":
				session.current_node_id = node["id"]
				session.run_state.set_car_wear(session.current_car_id, "rusty")
				var shown := ""
				for fact: Array in UI.stop_facts("errand", session, {}):
					if fact[0] == "TUNE-UP":
						shown = fact[1]
				if not _expect(str(session.errand_tune_steps()) in shown, "stop facts show this act's seeded repair strength"):
					return
				var result := session.resolve_errand(RunSession.ErrandChoice.TUNE_UP)
				tune_rewards[result.get("amount", 0)] = true
				break
	if not _expect(tune_rewards.size() >= 2, "errand repair rewards vary by seed"):
		return
	var app := root.get_node("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var session: RunSession = app.call("start_run", 900003)
	var starter := CarProfile.shape(session.car_stats(session.current_car_id))
	var won := session._add_car("recap-test", RunSession.CAR_ORIGIN_LOCKUP, RunSession.STARTER_TYPES)
	var shape := CarProfile.shape(session.car_stats(won))
	var largest := -INF
	var smallest := INF
	for axis: String in CarProfile.AXES:
		var difference := float(shape[axis]) - float(starter[axis])
		largest = maxf(largest, difference)
		smallest = minf(smallest, difference)
	# A temporary fitted part must not describe the car banked in the garage.
	session.installed_parts[won] = RunParts.deal(42, session.car_stats(won))
	app.call("abandon_run")
	var shell := app.get("_shell") as CanvasLayer
	shell.call("show_run_board")
	await process_frame
	var recap := shell.find_child("HaulRecap_" + won, true, false) as Label
	if not _expect(recap != null and ": " in recap.text and "VS STARTER" in recap.text, "banked recap names its stat comparison"):
		return
	for difference: float in [largest, smallest]:
		var delta := roundi(difference * 100.0)
		if delta != 0 and not _expect(("%+d " % delta) in recap.text, "recap shows the banked, unfitted car's strongest gain and loss"):
			return
	if not _expect(shell.find_child("ActionViewGarage", true, false) != null, "recap retains garage action"):
		return
	print("RUN_ECONOMY_DIVERSITY_TEST PASS seeds=48 acts=3")
	quit(0)

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_ECONOMY_DIVERSITY_TEST FAIL: " + message)
	quit(1)
	return false
