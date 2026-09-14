class_name CircuitLibrary
extends RefCounted

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const HISTORY_LIMIT := 12
const FAVORITES_LIMIT := 20


static func normalize_history(value: Variant) -> Array:
	return _normalize_entries(value, HISTORY_LIMIT)


static func normalize_favorites(value: Variant) -> Array:
	return _normalize_entries(value, FAVORITES_LIMIT)


static func add_recent(history_value: Variant, identity_value: Variant) -> Array:
	return _prepend_unique(history_value, identity_value, HISTORY_LIMIT)


static func add_favorite(favorites_value: Variant, identity_value: Variant) -> Array:
	return _prepend_unique(favorites_value, identity_value, FAVORITES_LIMIT)


static func remove_favorite(favorites_value: Variant, fingerprint: String) -> Array:
	var output: Array = []
	for entry: Dictionary in normalize_favorites(favorites_value):
		if String(entry["fingerprint"]) != fingerprint:
			output.append(entry.duplicate(true))
	return output


static func contains(favorites_value: Variant, fingerprint: String) -> bool:
	for entry: Dictionary in normalize_favorites(favorites_value):
		if String(entry["fingerprint"]) == fingerprint:
			return true
	return false


static func _prepend_unique(entries_value: Variant, identity_value: Variant, limit: int) -> Array:
	var identity := IDENTITIES.normalize(identity_value)
	if identity.is_empty():
		return _normalize_entries(entries_value, limit)
	var output: Array = [identity.duplicate(true)]
	var fingerprint := String(identity["fingerprint"])
	for entry: Dictionary in _normalize_entries(entries_value, limit):
		if String(entry["fingerprint"]) != fingerprint:
			output.append(entry.duplicate(true))
		if output.size() >= limit:
			break
	return output


static func _normalize_entries(value: Variant, limit: int) -> Array:
	var output: Array = []
	var seen := {}
	if value is not Array:
		return output
	for raw: Variant in value:
		var identity := IDENTITIES.normalize(raw)
		if identity.is_empty():
			continue
		var fingerprint := String(identity["fingerprint"])
		if seen.has(fingerprint):
			continue
		seen[fingerprint] = true
		output.append(identity.duplicate(true))
		if output.size() >= limit:
			break
	return output