class_name ChampionshipCircuitIdentity
extends RefCounted

const GENERATED_IDENTITY := preload("res://scripts/race/generated_circuit_identity.gd")
const SCHEMA_VERSION := 1
# Keep seeds/rooms stable while geometry revisions invalidate lap artifacts.
const SEED_VERSION := 1
const GENERATOR_VERSION := GENERATED_IDENTITY.GENERATOR_VERSION
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
	# Reserved: kept so the identity format does not change (see
	# GeneratedCircuitIdentity.DOMAINS).
	"hazard",
]


static func create_championship(championship_seed: int) -> Dictionary:
	var seed := clampi(championship_seed, 0, MAX_SEED)
	var events := {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		events[event_id] = create_event(seed, event)
	var identity := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"seed": seed,
		"events": events,
	}
	identity["fingerprint"] = _championship_fingerprint(identity)
	return identity


static func create_event(championship_seed: int, event: Dictionary) -> Dictionary:
	var event_id := String(event.get("id", ""))
	var theme := String(event.get("theme", ""))
	var sub_seeds := {}
	var fingerprints := {}
	for domain: String in DOMAINS:
		var sub_seed := _derive_sub_seed(championship_seed, event_id, domain)
		sub_seeds[domain] = sub_seed
		fingerprints[domain] = _domain_fingerprint(championship_seed, event_id, domain, sub_seed)
	var identity := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"championship_seed": championship_seed,
		"event_id": event_id,
		"theme": theme,
		"room": room_for_seed(int(sub_seeds["room_composition"])),
		"sub_seeds": sub_seeds,
		"fingerprints": fingerprints,
	}
	fingerprints["circuit"] = _event_fingerprint(identity)
	return identity


static func normalize_championship(value: Variant, fallback_seed: int = LEGACY_MIGRATION_SEED) -> Dictionary:
	if value is not Dictionary:
		return create_championship(fallback_seed)
	var raw := value as Dictionary
	if not _is_seed(raw.get("seed")):
		return create_championship(fallback_seed)
	var seed := int(raw["seed"])
	if int(raw.get("schema_version", 0)) != SCHEMA_VERSION or int(raw.get("generator_version", 0)) != GENERATOR_VERSION:
		return create_championship(seed)
	var raw_events: Dictionary = raw.get("events", {}) if raw.get("events") is Dictionary else {}
	var events := {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var normalized_event := _normalize_event(raw_events.get(event_id), event, seed)
		events[event_id] = normalized_event if not normalized_event.is_empty() else create_event(seed, event)
	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"seed": seed,
		"events": events,
	}
	normalized["fingerprint"] = _championship_fingerprint(normalized)
	return normalized


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


static func _normalize_event(value: Variant, event: Dictionary, championship_seed: int) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	if int(raw.get("schema_version", 0)) != SCHEMA_VERSION or int(raw.get("generator_version", 0)) != GENERATOR_VERSION:
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
		var expected_fingerprint := _domain_fingerprint(championship_seed, String(event["id"]), domain, seed)
		if String((raw_fingerprints as Dictionary).get(domain, "")) != expected_fingerprint:
			return {}
		sub_seeds[domain] = seed
		fingerprints[domain] = expected_fingerprint
	if room != room_for_seed(int(sub_seeds["room_composition"])):
		return {}
	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"championship_seed": championship_seed,
		"event_id": String(event["id"]),
		"theme": String(event["theme"]),
		"room": room,
		"sub_seeds": sub_seeds,
		"fingerprints": fingerprints,
	}
	var circuit_fingerprint := _event_fingerprint(normalized)
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


static func _domain_fingerprint(championship_seed: int, event_id: String, domain: String, sub_seed: int) -> String:
	return ("pc-circuit-domain-v%d|%d|%s|%s|%d" % [
		GENERATOR_VERSION,
		championship_seed,
		event_id,
		domain,
		sub_seed,
	]).sha256_text().substr(0, 16)


static func _event_fingerprint(identity: Dictionary) -> String:
	var parts := PackedStringArray([
		"pc-circuit-event-v%d" % GENERATOR_VERSION,
		str(identity["championship_seed"]),
		String(identity["event_id"]),
		String(identity["theme"]),
		String(identity["room"]),
	])
	var sub_seeds: Dictionary = identity["sub_seeds"]
	for domain: String in DOMAINS:
		parts.append("%s=%d" % [domain, int(sub_seeds[domain])])
	return "|".join(parts).sha256_text().substr(0, 16)


static func _championship_fingerprint(identity: Dictionary) -> String:
	var parts := PackedStringArray([
		"pc-championship-circuits-v%d" % GENERATOR_VERSION,
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
