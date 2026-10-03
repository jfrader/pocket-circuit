class_name DriverDirectory
extends RefCounted

## The one place driver ids resolve to identities.
##
## The shipped cast is the permanent roster of characters who exist outside any
## single tournament. A generated roster installs its opponents here for the
## duration of a quick race or championship, so every screen and the race itself
## keep looking drivers up by id and never need to know where they came from.

static var _generated: Dictionary = {}
static var _lead_id := ""


## Installs generated opponents in slot order, replacing any previous roster.
static func install_opponents(opponents: Array) -> void:
	_generated.clear()
	_lead_id = ""
	for entry: Variant in opponents:
		if entry is not Dictionary:
			continue
		var record := entry as Dictionary
		var driver_id := String(record.get("id", ""))
		if driver_id.is_empty():
			continue
		_generated[driver_id] = record.duplicate(true)
		if _lead_id.is_empty():
			_lead_id = driver_id


static func clear() -> void:
	_generated.clear()
	_lead_id = ""


static func is_empty() -> bool:
	return _generated.is_empty()


## Generated identities take precedence; the cast answers everything else.
static func get_driver(driver_id: String) -> Dictionary:
	var record: Variant = _generated.get(driver_id)
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


static func installed_ids() -> Array[String]:
	var ids: Array[String] = []
	for driver_id: Variant in _generated:
		ids.append(String(driver_id))
	return ids


## The roster's lead opponent, used wherever an act needs one face to represent it.
static func lead_id() -> String:
	return _lead_id
