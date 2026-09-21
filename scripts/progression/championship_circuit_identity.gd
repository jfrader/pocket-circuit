class_name ChampionshipCircuitIdentity
extends RefCounted

const GENERATED_IDENTITY := preload("res://scripts/race/generated_circuit_identity.gd")
const SCHEMA_VERSION := 1
# Keep seeds/rooms stable while geometry revisions invalidate lap artifacts.
const SEED_VERSION := 1
const GENERATOR_VERSION := GENERATED_IDENTITY.GENERATOR_VERSION
const V8_SCHEMA_VERSION := GENERATED_IDENTITY.V8_SCHEMA_VERSION
const V8_GENERATOR_VERSION := GENERATED_IDENTITY.V8_GENERATOR_VERSION
const LEGACY_MIGRATION_SEED := 665001
const MAX_SEED := 0x7FFFFFFF
const CIRCUIT_SEED_RANGE := 1000000
const CATALOG := preload("res://data/championship/catalog.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const ROOMS: Array[String] = GENERATED_RULES.ROOMS
const DOMAINS: Array[String] = [
	"route",
	"room_composition",
	"material",
	"dressing",
	"obstacle",
	"hazard",
]


static func create_championship(
		championship_seed: int,
		schema_version: int = SCHEMA_VERSION,
		generator_version: int = GENERATOR_VERSION
) -> Dictionary:
	if not _supported_version(schema_version, generator_version):
		return {}
	var seed := clampi(championship_seed, 0, MAX_SEED)
	var events := {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		events[event_id] = create_event(seed, event, schema_version, generator_version)
	var identity := {
		"schema_version": schema_version,
		"generator_version": generator_version,
		"seed": seed,
		"events": events,
	}
	identity["fingerprint"] = _championship_fingerprint(identity, generator_version)
	return identity


static func create_event(
		championship_seed: int,
		event: Dictionary,
		schema_version: int = SCHEMA_VERSION,
		generator_version: int = GENERATOR_VERSION
) -> Dictionary:
	if not _supported_version(schema_version, generator_version):
		return {}
	var event_id := String(event.get("id", ""))
	var theme := String(event.get("theme", ""))
	var sub_seeds := {}
	var fingerprints := {}
	for domain: String in DOMAINS:
		var sub_seed := _derive_sub_seed(championship_seed, event_id, domain)
		sub_seeds[domain] = sub_seed
		fingerprints[domain] = _domain_fingerprint(championship_seed, event_id, domain, sub_seed, generator_version)
	var identity := {
		"schema_version": schema_version,
		"generator_version": generator_version,
		"championship_seed": championship_seed,
		"event_id": event_id,
		"theme": theme,
		"room": room_for_seed(int(sub_seeds["room_composition"])),
		"sub_seeds": sub_seeds,
		"fingerprints": fingerprints,
	}
	if schema_version == V8_SCHEMA_VERSION:
		var generated := GENERATED_IDENTITY.create_v8(
			StringName(theme), StringName(identity["room"]), int(sub_seeds["route"]),
			false, int(event.get("act", 1)), "", "", sub_seeds
		)
		if generated.is_empty():
			return {}
		identity["room_recipe_id"] = int(generated["room_recipe_id"])
		identity["room_recipe_revision"] = int(generated["room_recipe_revision"])
		identity["room_geometry_seed"] = int(generated["room_geometry_seed"])
	fingerprints["circuit"] = _event_fingerprint(identity, generator_version)
	return identity


static func normalize_championship(value: Variant, fallback_seed: int = LEGACY_MIGRATION_SEED) -> Dictionary:
	var result := normalize_championship_result(value, fallback_seed)
	return (result.get("identity", {}) as Dictionary).duplicate(true) if bool(result.get("ok", false)) else {}


static func normalize_championship_result(value: Variant, fallback_seed: int = LEGACY_MIGRATION_SEED) -> Dictionary:
	if value is not Dictionary:
		return {"ok": true, "identity": create_championship(fallback_seed)}
	var raw := value as Dictionary
	if not _is_seed(raw.get("seed")):
		return _error("invalid_identity", "Championship circuit record has an invalid seed.")
	var seed := int(raw["seed"])
	if not _is_integral_number(raw.get("schema_version")) or not _is_integral_number(raw.get("generator_version")):
		return _error("missing_version", "Championship circuit record requires explicit schema and generator versions.")
	var schema_version := int(raw["schema_version"])
	var generator_version := int(raw["generator_version"])
	if not _supported_version(schema_version, generator_version):
		return _error("unsupported_generator", "Championship circuit schema %d generator %d is not supported." % [schema_version, generator_version])
	var raw_events: Dictionary = raw.get("events", {}) if raw.get("events") is Dictionary else {}
	var events := {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var normalized_event := _normalize_event(raw_events.get(event_id), event, seed, schema_version, generator_version)
		events[event_id] = normalized_event if not normalized_event.is_empty() else create_event(seed, event, schema_version, generator_version)
	var normalized := {
		"schema_version": schema_version,
		"generator_version": generator_version,
		"seed": seed,
		"events": events,
	}
	normalized["fingerprint"] = _championship_fingerprint(normalized, generator_version)
	return {"ok": true, "identity": normalized}


static func event_identity(championship: Dictionary, event_id: String) -> Dictionary:
	var events: Variant = championship.get("events")
	if events is not Dictionary:
		return {}
	var identity: Variant = (events as Dictionary).get(event_id)
	return (identity as Dictionary).duplicate(true) if identity is Dictionary else {}


static func apply_to_event(event: Dictionary, identity: Dictionary) -> Dictionary:
	if identity.is_empty():
		return event.duplicate(true)
	var output := event.duplicate(true)
	var sub_seeds: Dictionary = identity.get("sub_seeds", {})
	var fingerprints: Dictionary = identity.get("fingerprints", {})
	output["circuit"] = "generated"
	output["room"] = String(identity.get("room", "classic"))
	output["seed"] = int(sub_seeds.get("route", 0))
	output["circuit_schema_version"] = int(identity.get("schema_version", 0))
	output["circuit_generator_version"] = int(identity.get("generator_version", 0))
	output["circuit_fingerprint"] = String(fingerprints.get("circuit", ""))
	output["circuit_identity"] = identity.duplicate(true)
	var generated_identity := GENERATED_IDENTITY.from_championship_event(output, identity)
	if not generated_identity.is_empty():
		output["generated_circuit_identity"] = generated_identity
		output["circuit_display_name"] = String(generated_identity["display_name"])
		output["circuit_summary"] = String(generated_identity["summary"])
	return output


static func room_for_seed(seed: int) -> String:
	return String(GENERATED_RULES.room_for_composition_seed(seed))


static func _normalize_event(
		value: Variant,
		event: Dictionary,
		championship_seed: int,
		schema_version: int,
		generator_version: int
) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	if int(raw.get("schema_version", 0)) != schema_version or int(raw.get("generator_version", 0)) != generator_version:
		return {}
	if not _is_seed(raw.get("championship_seed")) or int(raw["championship_seed"]) != championship_seed:
		return {}
	if String(raw.get("event_id", "")) != String(event["id"]) or String(raw.get("theme", "")) != String(event["theme"]):
		return {}
	var room := String(raw.get("room", ""))
	if not room in ROOMS:
		return {}
	var raw_seeds: Variant = raw.get("sub_seeds")
	var raw_fingerprints: Variant = raw.get("fingerprints")
	if raw_seeds is not Dictionary or raw_fingerprints is not Dictionary:
		return {}
	var sub_seeds := {}
	var fingerprints := {}
	for domain: String in DOMAINS:
		var seed_value: Variant = (raw_seeds as Dictionary).get(domain)
		if not _is_seed(seed_value):
			return {}
		var seed := int(seed_value)
		if seed != _derive_sub_seed(championship_seed, String(event["id"]), domain):
			return {}
		var expected_fingerprint := _domain_fingerprint(championship_seed, String(event["id"]), domain, seed, generator_version)
		if String((raw_fingerprints as Dictionary).get(domain, "")) != expected_fingerprint:
			return {}
		sub_seeds[domain] = seed
		fingerprints[domain] = expected_fingerprint
	if room != room_for_seed(int(sub_seeds["room_composition"])):
		return {}
	var normalized := {
		"schema_version": schema_version,
		"generator_version": generator_version,
		"championship_seed": championship_seed,
		"event_id": String(event["id"]),
		"theme": String(event["theme"]),
		"room": room,
		"sub_seeds": sub_seeds,
		"fingerprints": fingerprints,
	}
	if schema_version == V8_SCHEMA_VERSION:
		for field: String in ["room_recipe_id", "room_recipe_revision", "room_geometry_seed"]:
			if not _is_integral_number(raw.get(field)):
				return {}
			normalized[field] = int(raw[field])
		var generated := GENERATED_IDENTITY.from_championship_event(event, normalized)
		if generated.is_empty():
			return {}
	var circuit_fingerprint := _event_fingerprint(normalized, generator_version)
	if String((raw_fingerprints as Dictionary).get("circuit", "")) != circuit_fingerprint:
		return {}
	fingerprints["circuit"] = circuit_fingerprint
	return normalized


static func _derive_sub_seed(championship_seed: int, event_id: String, domain: String) -> int:
	var value := 0x13579BDF
	var key := "pocket-circuit|championship-circuit|generator=%d|seed=%d|event=%s|domain=%s" % [
		SEED_VERSION,
		championship_seed,
		event_id,
		domain,
	]
	for byte: int in key.to_utf8_buffer():
		value = (value * 1103515245 + byte + 12345) & MAX_SEED
		value = (value ^ (value >> 11)) & MAX_SEED
	return posmod(value, CIRCUIT_SEED_RANGE)


static func _domain_fingerprint(championship_seed: int, event_id: String, domain: String, sub_seed: int, generator_version: int = GENERATOR_VERSION) -> String:
	return ("pc-circuit-domain-v%d|%d|%s|%s|%d" % [
		generator_version,
		championship_seed,
		event_id,
		domain,
		sub_seed,
	]).sha256_text().substr(0, 16)


static func _event_fingerprint(identity: Dictionary, generator_version: int = GENERATOR_VERSION) -> String:
	var parts := PackedStringArray([
		"pc-circuit-event-v%d" % generator_version,
		str(identity["championship_seed"]),
		String(identity["event_id"]),
		String(identity["theme"]),
		String(identity["room"]),
	])
	if generator_version == V8_GENERATOR_VERSION:
		parts.append("recipe=%d:%d" % [int(identity["room_recipe_id"]), int(identity["room_recipe_revision"])])
		parts.append("room_geometry=%d" % int(identity["room_geometry_seed"]))
	var sub_seeds: Dictionary = identity["sub_seeds"]
	for domain: String in DOMAINS:
		parts.append("%s=%d" % [domain, int(sub_seeds[domain])])
	return "|".join(parts).sha256_text().substr(0, 16)


static func _championship_fingerprint(identity: Dictionary, generator_version: int = GENERATOR_VERSION) -> String:
	var parts := PackedStringArray([
		"pc-championship-circuits-v%d" % generator_version,
		str(identity["seed"]),
	])
	var events: Dictionary = identity["events"]
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var event_identity_value: Dictionary = events[event_id]
		parts.append("%s=%s" % [event_id, String(event_identity_value["fingerprints"]["circuit"])])
	return "|".join(parts).sha256_text().substr(0, 16)


static func _is_seed(value: Variant) -> bool:
	if value is not int and value is not float:
		return false
	var seed := int(value)
	return seed >= 0 and seed <= MAX_SEED and float(seed) == float(value)


static func _supported_version(schema_version: int, generator_version: int) -> bool:
	return (
		(schema_version == SCHEMA_VERSION and generator_version == GENERATOR_VERSION)
		or (schema_version == V8_SCHEMA_VERSION and generator_version == V8_GENERATOR_VERSION)
	)


static func _is_integral_number(value: Variant) -> bool:
	return (value is int or value is float) and float(int(value)) == float(value)


static func _error(kind: String, message: String) -> Dictionary:
	return {"ok": false, "kind": kind, "error": message}
