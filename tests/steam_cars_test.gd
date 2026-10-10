extends SceneTree

## GURI-2114 (Won cars drop as tradable Steam inventory items): the item
## definitions uploaded to Steamworks decode back into cars, every client
## rebuilds the same car from an item, and the game asks Steam for a drop when
## a run wins a car, mirrors the inventory into Quick Race and keeps it offline.

const RUN_STATE := preload("res://scripts/progression/run_state.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const STEAM_SERVICE := preload("res://scripts/steam/steam_service.gd")


## Stands in for the GodotSteam singleton: hands out handles and answers them
## when told to, the way Steam's callbacks arrive later.
class FakeSteam:
	extends RefCounted
	signal inventory_result_ready(result: int, handle: int)
	var owned: Array[Dictionary] = []
	var drop_due := true
	var next_item_id := 7000
	var drops := 0
	var destroyed: Array[int] = []
	var _results := {}
	var _next_handle := 1

	func getAllItems() -> int:
		return _open(owned.duplicate(true))

	func triggerItemDrop(definition: int) -> int:
		drops += 1
		var items: Array[Dictionary] = []
		if drop_due and definition == SteamCars.GENERATOR_ID:
			next_item_id += 1
			var item := {"item_id": next_item_id, "item_definition": SteamCars.CAR_ITEM_IDS["coupe"], "tags": "pace:b8;bite:b0;punch:b4;livery:l17"}
			owned.append(item)
			items.append(item)
		return _open(items)

	func getResultItems(handle: int) -> Array:
		return (_results[handle] as Array).map(func(item: Dictionary) -> Dictionary: return {"item_id": item["item_id"], "item_definition": item["item_definition"], "flags": 0, "quantity": 1})

	func getResultItemProperty(index: int, name: String, handle: int) -> String:
		return String((_results[handle] as Array)[index].get(name, "")) if name == "tags" else ""

	func destroyResult(handle: int) -> void:
		destroyed.append(handle)

	func answer(result: int = STEAM_SERVICE.RESULT_OK) -> void:
		for handle: int in _results.keys():
			if not destroyed.has(handle):
				inventory_result_ready.emit(result, handle)

	func _open(items: Array[Dictionary]) -> int:
		var handle := _next_handle
		_next_handle += 1
		_results[handle] = items
		return handle


var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for check: Callable in [_check_itemdefs, _check_decode]:
		check.call()
		if _failed:
			return
	await _check_service()
	if _failed:
		return
	await _check_app()
	if _failed:
		return
	print("STEAM_CARS_TEST PASS")
	quit(0)


## The uploaded definitions: one tradable, unmarketable item per generator car
## type, a hidden playtime generator over all of them with the tag generators,
## and every value a tag generator can roll decodes into a car.
func _check_itemdefs() -> void:
	var defs: Dictionary = SteamCars.itemdefs(480)
	var by_id := {}
	for item: Dictionary in defs["items"]:
		by_id[int(item["itemdefid"])] = item
	if not _expect(int(defs["appid"]) == 480 and by_id.size() == (defs["items"] as Array).size(), "item definitions carry the app id and unique ids"):
		return
	if not _expect(SteamCars.CAR_ITEM_IDS.keys().all(func(car_type: String) -> bool: return car_type in ProceduralCarGenerator.SUPPORTED_TYPES) and SteamCars.CAR_ITEM_IDS.size() == ProceduralCarGenerator.SUPPORTED_TYPES.size(), "every generator car type has an item, and only those"):
		return
	for car_type: String in SteamCars.CAR_ITEM_IDS:
		var item: Dictionary = by_id[SteamCars.CAR_ITEM_IDS[car_type]]
		if not _expect(item["type"] == "item" and item["tradable"] == true and item["marketable"] == false, "%s cars trade and stay off the market" % car_type):
			return
	var generator: Dictionary = by_id[SteamCars.GENERATOR_ID]
	if not _expect(generator["type"] == "playtimegenerator" and generator["hidden"] == true, "the drop is a hidden playtime generator"):
		return
	for car_type: String in SteamCars.CAR_ITEM_IDS:
		if not _expect(String(generator["bundle"]).split(";").has("%dx%d" % [SteamCars.CAR_ITEM_IDS[car_type], SteamCars.TYPE_WEIGHTS[car_type]]), "the drop can roll a %s" % car_type):
			return
	var generators := String(generator["tag_generators"]).split(";")
	var values := {}
	for tag: String in SteamCars.TAG_GENERATOR_IDS:
		var tag_def: Dictionary = by_id[SteamCars.TAG_GENERATOR_IDS[tag]]
		if not _expect(generators.has(str(SteamCars.TAG_GENERATOR_IDS[tag])) and tag_def["type"] == "tag_generator" and tag_def["tag_generator_name"] == tag, "the drop rolls the %s tag" % tag):
			return
		values[tag] = Array(String(tag_def["tag_generator_values"]).split(";")).map(func(token: String) -> String: return token.split(":")[0])
	for car_type: String in SteamCars.CAR_ITEM_IDS:
		for pace: String in values["pace"]:
			var tags := "pace:%s;bite:%s;punch:%s;livery:%s" % [pace, values["bite"][0], values["punch"][-1], values["livery"][-1]]
			if not _expect(not SteamCars.car_from_item(SteamCars.CAR_ITEM_IDS[car_type], 1, tags).is_empty(), "every rolled value decodes (%s %s)" % [car_type, tags]):
				return


## An item is the same car everywhere: zero-sum like a run roll, inside its
## type's envelope, the middle buckets level, and anything else is no car.
func _check_decode() -> void:
	var tags := "type:muscle;pace:b8;bite:b2;punch:b4;livery:l9"
	var car := SteamCars.car_from_item(SteamCars.CAR_ITEM_IDS["muscle"], 4242, tags)
	if not _expect(car == SteamCars.car_from_item(SteamCars.CAR_ITEM_IDS["muscle"], 4242, "livery:l9;punch:b4;bite:b2;pace:b8"), "the same item rebuilds the same car, whatever the tag order"):
		return
	var envelope := RUN_STATE.get_envelope_for_type("muscle")
	if not _expect(car["id"] == "steam-4242" and car["type"] == "muscle" and car["won_from"] == SteamCars.ORIGIN and is_equal_approx(car["roll"]["speed"], envelope) and is_equal_approx(car["roll"]["tough"], -envelope) and is_zero_approx(car["roll"]["accel"]), "buckets set the pair deviations across the type's envelope"):
		return
	if not _expect(is_zero_approx(RUN_STATE.sum_of_axes(car["roll"])) and RUN_STATE.max_abs_deviation(car["roll"]) <= envelope + 0.0001, "a Steam car is zero-sum inside its envelope"):
		return
	if not _expect(not RunSession.normalize_car(car, [SteamCars.ORIGIN]).is_empty(), "a Steam car passes the stored-car check"):
		return
	var other := SteamCars.car_from_item(SteamCars.CAR_ITEM_IDS["muscle"], 4243, "pace:b8;bite:b2;punch:b4;livery:l10")
	if not _expect(other["seed"] != car["seed"], "a different livery is a different look"):
		return
	for bad: Array in [[999, "pace:b4;bite:b4;punch:b4;livery:l0"], [SteamCars.CAR_ITEM_IDS["buggy"], "pace:b4;bite:b4;punch:b4"], [SteamCars.CAR_ITEM_IDS["buggy"], "pace:b9;bite:b4;punch:b4;livery:l0"], [SteamCars.CAR_ITEM_IDS["buggy"], "pace:b4;bite:b4;punch:b4;livery:l256"]]:
		if not _expect(SteamCars.car_from_item(int(bad[0]), 1, String(bad[1])).is_empty(), "an item that is not a whole car decodes to nothing (%s)" % str(bad)):
			return


## The service: a drop announces its car and refreshes the inventory; no drop
## due, a failed result, or no Steam at all does nothing; every handle is freed.
func _check_service() -> void:
	var service: Node = STEAM_SERVICE.new()
	root.add_child(service)
	var seen := {"dropped": [], "changed": []}
	service.car_dropped.connect(func(car: Dictionary) -> void: seen["dropped"].append(car))
	service.cars_changed.connect(func(cars: Array[Dictionary]) -> void: seen["changed"].append(cars))
	service.trigger_car_drop()
	service.refresh()
	if not _expect(not service.is_available() and seen["dropped"].is_empty() and seen["changed"].is_empty(), "without Steam every call does nothing"):
		return
	var fake := FakeSteam.new()
	if not _expect(service.connect_steam(fake) and service.is_available(), "a backend connects"):
		return
	fake.drop_due = false
	service.trigger_car_drop()
	fake.answer()
	if not _expect(seen["dropped"].is_empty() and seen["changed"].is_empty() and fake.destroyed.size() == 1, "no drop due announces nothing and frees its handle"):
		return
	fake.drop_due = true
	service.trigger_car_drop()
	fake.answer(2)
	if not _expect(seen["dropped"].is_empty() and fake.destroyed.size() == 2, "a failed result announces nothing and frees its handle"):
		return
	service.trigger_car_drop()
	fake.answer()
	fake.answer()
	if not _expect(seen["dropped"].size() == 1 and String(seen["dropped"][0]["type"]) == "coupe" and seen["changed"].size() == 1 and (seen["changed"][0] as Array).size() == 2, "a drop announces its car, then the inventory refreshes"):
		return
	if not _expect(fake.destroyed.size() == 4, "every answered handle is freed"):
		return
	service.queue_free()


## The game: a run win asks for a drop, the drop is announced over the run
## screen, and the inventory lands in Quick Race and in the save.
func _check_app() -> void:
	var app := root.get_node_or_null("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var fake := FakeSteam.new()
	if not _expect(not app.get("steam").is_available() and app.get("steam").connect_steam(fake), "tests start without Steam, and a fake connects"):
		return
	var sess: RunSession
	for attempt in 12:
		sess = app.call("start_run", 1827000 + attempt * 31) as RunSession
		if RUN_WALK.walk_to(app, sess, "rival"):
			break
	shell.call("show_run_board")
	RUN_WALK.settle(app, sess)
	if not _expect(not sess.pending_offer.is_empty() and fake.drops == 1, "winning a duel asks Steam for a drop"):
		return
	fake.answer()
	await process_frame
	await process_frame
	if not _expect(shell.find_child("SteamDrop", true, false) != null and Dictionary(app.get("steam_drop")).is_empty(), "the drop is announced once over the run screen"):
		return
	fake.answer()
	var steam_cars: Array = app.call("get_save_data")["steam_cars"]
	var dropped_id := String(steam_cars[0]["id"]) if not steam_cars.is_empty() else ""
	if not _expect(steam_cars.size() == 1 and (app.call("quick_race_roster") as Array).has(dropped_id) and not CATALOG.get_vehicle(dropped_id).is_empty(), "the Steam car is in Quick Race and resolves like any car"):
		return
	var saved: Dictionary = SAVE_STORE.new(String(app.get("_save_store").get("save_path"))).load_data()
	if not _expect((saved["steam_cars"] as Array).size() == 1 and String(saved["steam_cars"][0]["id"]) == dropped_id, "the save keeps the inventory for offline play"):
		return
	fake.owned.clear()
	app.get("steam").refresh()
	fake.answer()
	if not _expect((app.call("get_save_data")["steam_cars"] as Array).is_empty() and not (app.call("quick_race_roster") as Array).has(dropped_id), "a car traded away leaves the garage"):
		return
	app.call("abandon_run")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("STEAM_CARS_TEST FAIL: " + message)
	quit(1)
	return false
