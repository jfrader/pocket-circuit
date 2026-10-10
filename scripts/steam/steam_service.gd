extends Node

## The game's one door to Steam. Steam is optional: without the GodotSteam
## extension, without the Steam client, or in tests, every call does nothing
## and the game plays the same.
##
## Inventory calls return a handle at once; the result arrives through the
## backend's inventory_result_ready signal, exactly once per handle, and each
## handle is destroyed once read.
##   refresh()          reads every item the player owns -> cars_changed
##   trigger_car_drop() asks the playtime generator for a drop -> car_dropped
##                      (nothing when no drop is due), then refreshes

signal cars_changed(cars: Array[Dictionary])
signal car_dropped(car: Dictionary)

const SINGLETON := "Steam"
## A development app id for runs outside the Steam client; Steam itself
## supplies the id when it launches the game.
const APP_ID_ENV := "POCKET_CIRCUIT_STEAM_APP_ID"
const INIT_OK := 0
const RESULT_OK := 1
const TAGS_PROPERTY := "tags"

var _backend: Object = null
var _pending: Dictionary = {}


## Connects to the Steam client when the extension is installed; tests pass
## their own backend instead.
func connect_steam(backend: Object = null) -> bool:
	if backend == null and Engine.has_singleton(SINGLETON):
		var steam := Engine.get_singleton(SINGLETON)
		var init: Dictionary = steam.call("steamInitEx", int(OS.get_environment(APP_ID_ENV)), true)
		if int(init.get("status", -1)) == INIT_OK:
			backend = steam
	if backend == null:
		return false
	_backend = backend
	_backend.connect("inventory_result_ready", _on_result_ready)
	return true


func is_available() -> bool:
	return _backend != null


func refresh() -> void:
	_request("getAllItems", [], "all")


func trigger_car_drop() -> void:
	_request("triggerItemDrop", [SteamCars.GENERATOR_ID], "drop")


func _request(method: String, args: Array, kind: String) -> void:
	if _backend == null:
		return
	var handle := int(_backend.callv(method, args))
	if handle > 0:
		_pending[handle] = kind


func _on_result_ready(result: int, handle: int) -> void:
	if not _pending.has(handle):
		return
	var kind := String(_pending[handle])
	_pending.erase(handle)
	var cars := _read_cars(handle) if result == RESULT_OK else ([] as Array[Dictionary])
	_backend.call("destroyResult", handle)
	if result != RESULT_OK:
		return
	if kind == "all":
		cars_changed.emit(cars)
		return
	for car: Dictionary in cars:
		car_dropped.emit(car)
	if not cars.is_empty():
		refresh()


func _read_cars(handle: int) -> Array[Dictionary]:
	var cars: Array[Dictionary] = []
	var items: Array = _backend.call("getResultItems", handle)
	for index: int in items.size():
		var item: Dictionary = items[index]
		var tags := String(_backend.call("getResultItemProperty", index, TAGS_PROPERTY, handle))
		var car := SteamCars.car_from_item(int(item.get("item_definition", 0)), int(item.get("item_id", 0)), tags)
		if not car.is_empty():
			cars.append(car)
	return cars
