class_name VehicleDirectory
extends RefCounted

## The one place generated vehicle ids resolve, beside the shipped catalog.
##
## Cars won in a run are generated, not authored. The App installs every one
## the player holds (the garage and the active run) here, so the race, the
## menus and audio keep looking vehicles up by id and never need to know where
## a car came from.

static var _generated: Dictionary = {}


## Replaces the installed set with these described vehicles.
static func install(vehicles: Array) -> void:
	_generated.clear()
	for entry: Variant in vehicles:
		if entry is Dictionary and not String((entry as Dictionary).get("id", "")).is_empty():
			_generated[String(entry["id"])] = (entry as Dictionary).duplicate(true)


static func clear() -> void:
	_generated.clear()


static func get_vehicle(vehicle_id: String) -> Dictionary:
	var record: Variant = _generated.get(vehicle_id)
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


static func installed_ids() -> Array[String]:
	var ids: Array[String] = []
	for vehicle_id: Variant in _generated:
		ids.append(String(vehicle_id))
	return ids
