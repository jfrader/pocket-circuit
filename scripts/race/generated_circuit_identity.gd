class_name GeneratedCircuitIdentity
extends RefCounted

const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const SCHEMA_VERSION := 1
const GENERATOR_VERSION := 7
const V8_SCHEMA_VERSION := 2
const V8_GENERATOR_VERSION := 8
const MAX_SEED := 0x7FFFFFFF
const SHARE_PREFIX := "PC1"
const SHARE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const MAX_EXPLICIT_ID_LENGTH := 24
const DOMAINS: Array[String] = [
	"route",
	"room_composition",
	"material",
	"dressing",
	"obstacle",
	"hazard",
]
const THEMES: Array[String] = ["kitchen", "workshop", "office"]
const ROOMS: Array[String] = GENERATED_RULES.ROOMS
const V8_ROOM_RECIPES := {
	0: {"family": "classic", "revision": 1},
	1: {"family": "wide", "revision": 1},
	2: {"family": "tall", "revision": 1},
	3: {"family": "long", "revision": 1},
	4: {"family": "square", "revision": 1},
	5: {"family": "el", "revision": 1},
}
const THEME_NOUNS := {
	"kitchen": ["Teacup", "Spoon", "Crumb", "Counter", "Saucers", "Pepper"],
	"workshop": ["Rivet", "Wrench", "Sawdust", "Workbench", "Socket", "Clamp"],
	"office": ["Paperclip", "Keycap", "Notepad", "Desktop", "Pencil", "Stapler"],
}
const NAME_ADJECTIVES := ["Copper", "Pocket", "Clockwork", "Bright", "Midnight", "Rapid", "Tiny", "Hidden"]



static func create(
		theme: StringName,
		room: StringName,
		route_seed: int,
		reverse: bool = false,
		danger_level: int = 0,
		explicit_material_id: String = "",
		explicit_palette_id: String = "",
		sub_seed_overrides: Dictionary = {},
		length_tier: String = "standard"
) -> Dictionary:
	var theme_text := String(theme)
	var room_text := String(room)
	if not theme_text in THEMES or not room_text in ROOMS or not _is_seed(route_seed):
		return {}
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return {}
	var level := clampi(danger_level if danger_level > 0 else GENERATED_RULES.default_act_for_theme(theme), 1, 3)
	var seeds := {
		"route": route_seed,
		"room_composition": _room_composition_seed_for_room(route_seed, room_text),
		"material": _mix_seed(route_seed, "material"),
		"dressing": _mix_seed(route_seed, theme_text),
		"obstacle": _mix_seed(route_seed, "obstacle_plan"),
		"hazard": _mix_seed(route_seed, "hazard_plan"),
	}
	for domain: String in DOMAINS:
		if sub_seed_overrides.has(domain):
			seeds[domain] = sub_seed_overrides[domain]
	if int(seeds.get("route", -1)) != route_seed:
		return {}
	return _canonical_identity(theme_text, room_text, reverse, level, explicit_material_id, explicit_palette_id, seeds, length_tier)


static func create_v8(
		theme: StringName,
		room: StringName,
		route_seed: int,
		reverse: bool = false,
		danger_level: int = 0,
		explicit_material_id: String = "",
		explicit_palette_id: String = "",
		sub_seed_overrides: Dictionary = {},
		length_tier: String = "standard",
		room_recipe_id: int = -1,
		room_recipe_revision: int = 1,
		room_geometry_seed: int = -1
) -> Dictionary:
	var theme_text := String(theme)
	var room_text := String(room)
	if not theme_text in THEMES or not room_text in ROOMS or not _is_seed(route_seed):
		return {}
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return {}
	if room_recipe_id < 0:
		room_recipe_id = ROOMS.find(room_text)
	var level := clampi(danger_level if danger_level > 0 else GENERATED_RULES.default_act_for_theme(theme), 1, 3)
	var seeds := {
		"route": route_seed,
		"room_composition": _room_composition_seed_for_room(route_seed, room_text),
		"material": _mix_seed(route_seed, "material"),
		"dressing": _mix_seed(route_seed, theme_text),
		"obstacle": _mix_seed(route_seed, "obstacle_plan"),
		"hazard": _mix_seed(route_seed, "hazard_plan"),
	}
	for domain: String in DOMAINS:
		if sub_seed_overrides.has(domain):
			seeds[domain] = sub_seed_overrides[domain]
	if int(seeds.get("route", -1)) != route_seed:
		return {}
	if room_geometry_seed < 0:
		room_geometry_seed = _v8_room_geometry_seed(int(seeds["room_composition"]), room_recipe_id, room_recipe_revision)
	return _canonical_identity_v8(
		theme_text, room_text, reverse, level, explicit_material_id, explicit_palette_id,
		seeds, length_tier, room_recipe_id, room_recipe_revision, room_geometry_seed
	)


static func from_championship_event(event: Dictionary, championship_identity: Dictionary) -> Dictionary:
	var seeds: Variant = championship_identity.get("sub_seeds")
	if seeds is not Dictionary:
		return {}
	var schema := int(championship_identity.get("schema_version", 0))
	var generator := int(championship_identity.get("generator_version", 0))
	if schema == V8_SCHEMA_VERSION and generator == V8_GENERATOR_VERSION:
		return _canonical_identity_v8(
			String(event.get("theme", championship_identity.get("theme", ""))),
			String(championship_identity.get("room", event.get("room", ""))),
			bool(event.get("reverse", false)),
			clampi(int(event.get("act", 1)), 1, 3),
			String(championship_identity.get("material_id", "")),
			String(championship_identity.get("palette_id", "")),
			seeds as Dictionary,
			String(event.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)),
			int(championship_identity.get("room_recipe_id", -1)),
			int(championship_identity.get("room_recipe_revision", -1)),
			int(championship_identity.get("room_geometry_seed", -1))
		)
	if schema != SCHEMA_VERSION or generator != GENERATOR_VERSION:
		return {}
	return _canonical_identity(
		String(event.get("theme", championship_identity.get("theme", ""))),
		String(championship_identity.get("room", event.get("room", ""))),
		bool(event.get("reverse", false)),
		clampi(int(event.get("act", 1)), 1, 3),
		String(championship_identity.get("material_id", "")),
		String(championship_identity.get("palette_id", "")),
		seeds as Dictionary
	)


static func normalize(value: Variant) -> Dictionary:
	var result := normalize_result(value)
	return (result.get("identity", {}) as Dictionary).duplicate(true) if bool(result.get("ok", false)) else {}


static func normalize_result(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return _error("invalid_identity", "Circuit identity must be a dictionary.")
	var raw := value as Dictionary
	var version_result := _version_pair(raw)
	if not bool(version_result.get("ok", false)):
		return version_result
	var schema := int(version_result["schema_version"])
	var generator := int(version_result["generator_version"])
	if schema == V8_SCHEMA_VERSION and generator == V8_GENERATOR_VERSION:
		return _normalize_v8(raw)
	if schema != SCHEMA_VERSION or generator != GENERATOR_VERSION:
		return _unsupported_version(schema, generator)
	if raw.get("theme") is not String or raw.get("room") is not String:
		return _error("invalid_identity", "Circuit identity has an invalid theme or room.")
	if raw.get("reverse") is not bool or raw.get("material_id") is not String or raw.get("palette_id") is not String:
		return _error("invalid_identity", "Circuit identity has invalid direction or material fields.")
	var danger_value: Variant = raw.get("danger_level")
	if (danger_value is not int and danger_value is not float) or float(int(danger_value)) != float(danger_value):
		return _error("invalid_identity", "Circuit identity has an invalid danger level.")
	var seeds: Variant = raw.get("sub_seeds")
	if seeds is not Dictionary:
		return _error("invalid_identity", "Circuit identity is missing its sub-seeds.")
	var length_tier: Variant = raw.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)
	if length_tier is not String or not GENERATED_RULES.LENGTH_TIERS.has(length_tier as String):
		return _error("invalid_identity", "Circuit identity has an unknown length profile.")
	var canonical := _canonical_identity(
		String(raw.get("theme", "")),
		String(raw.get("room", "")),
		bool(raw["reverse"]),
		int(raw.get("danger_level", 0)),
		String(raw.get("material_id", "")),
		String(raw.get("palette_id", "")),
		seeds as Dictionary,
		String(length_tier)
	)
	if canonical.is_empty():
		return _error("invalid_identity", "Circuit identity fields are inconsistent.")
	if raw.has("fingerprint") and String(raw["fingerprint"]) != String(canonical["fingerprint"]):
		return _error("fingerprint", "Circuit identity fingerprint does not match its fields.")
	return {"ok": true, "identity": canonical}


static func apply_to_event(identity_value: Variant, vehicle_opponents: Array = ["juniper", "milo", "tess"]) -> Dictionary:
	var identity := normalize(identity_value)
	if identity.is_empty():
		return {}
	var seeds: Dictionary = identity["sub_seeds"]
	return {
		"id": "discovery_%s" % String(identity["fingerprint"]),
		"name": String(identity["display_name"]),
		"circuit_display_name": String(identity["display_name"]),
		"circuit_summary": String(identity["summary"]),
		"theme": String(identity["theme"]),
		"room": String(identity["room"]),
		"seed": int(seeds["route"]),
		"circuit": "generated",
		"race_format": "circuit",
		"reverse": bool(identity["reverse"]),
		"act": int(identity["danger_level"]),
		"length_tier": String(identity["length_tier"]),
		"opponent_count": mini(3, vehicle_opponents.size()),
		"opponents": vehicle_opponents.duplicate(),
		"circuit_schema_version": int(identity["schema_version"]),
		"circuit_generator_version": int(identity["generator_version"]),
		"circuit_fingerprint": String(identity["fingerprint"]),
		"circuit_identity": identity.duplicate(true),
		"generated_circuit_identity": identity.duplicate(true),
	}


static func display_name(identity_value: Variant) -> String:
	var identity := normalize(identity_value)
	return String(identity.get("display_name", "Unknown Circuit"))


static func summary(identity_value: Variant) -> String:
	var identity := normalize(identity_value)
	return String(identity.get("summary", "Circuit identity is invalid"))


static func encode_share_code(identity_value: Variant) -> Dictionary:
	var normalized := normalize_result(identity_value)
	if not bool(normalized.get("ok", false)):
		return normalized
	var identity: Dictionary = normalized["identity"]
	var material_id := String(identity["material_id"])
	var palette_id := String(identity["palette_id"])
	var derived := WORLD_MATERIALS.resolve(
		StringName(identity["theme"]),
		StringName(identity["story_id"]),
		int((identity["sub_seeds"] as Dictionary)["material"])
	)
	if material_id == String(derived["material_id"]) and palette_id == String(derived["palette_id"]):
		material_id = ""
		palette_id = ""
	var schema := int(identity["schema_version"])
	var generator := int(identity["generator_version"])
	var payload := PackedByteArray([
		generator,
		THEMES.find(String(identity["theme"])),
		ROOMS.find(String(identity["room"])),
		1 if bool(identity["reverse"]) else 0,
		int(identity["danger_level"]),
		GENERATED_RULES.LENGTH_TIERS.find(String(identity["length_tier"])),
	])
	if schema == V8_SCHEMA_VERSION:
		payload.append(int(identity["room_recipe_id"]))
		payload.append(int(identity["room_recipe_revision"]))
		_append_u32(payload, int(identity["room_geometry_seed"]))
	var seeds: Dictionary = identity["sub_seeds"]
	for domain: String in DOMAINS:
		_append_u32(payload, int(seeds[domain]))
	_append_short_string(payload, material_id)
	_append_short_string(payload, palette_id)
	var checksum := _checksum(payload)
	payload.append_array(checksum)
	var compact := "PC%d" % schema + _base32_encode(payload)
	return {"ok": true, "code": _group_code(compact), "identity": identity.duplicate(true)}


static func decode_share_code(code: String) -> Dictionary:
	var entered := code.strip_edges().to_upper().replace(" ", "")
	if entered.length() < 4 or not entered.begins_with("PC"):
		return _error("format", "Enter a Pocket Circuit code beginning with PC1.")
	var first_dash := entered.find("-")
	var schema_text := entered.substr(2, first_dash - 2) if first_dash >= 0 else entered.substr(2, 1)
	var payload_text := entered.substr(first_dash + 1).replace("-", "") if first_dash >= 0 else entered.substr(3)
	if schema_text.is_empty() or not schema_text.is_valid_int():
		return _error("format", "The share code is missing its schema version.")
	var schema := int(schema_text)
	if schema_text != str(schema):
		return _error("format", "Use the canonical share-code schema spelling PC%d." % schema)
	if schema not in [SCHEMA_VERSION, V8_SCHEMA_VERSION]:
		return _error("unsupported_schema", "Share-code version PC%d is not supported by this build." % schema)
	var decoded := _base32_decode(payload_text)
	if not bool(decoded.get("ok", false)):
		return decoded
	var bytes: PackedByteArray = decoded["bytes"]
	var minimum_size := 42 if schema == V8_SCHEMA_VERSION else 36
	if bytes.size() < minimum_size:
		return _error("truncated", "The share code is incomplete; enter every character.")
	var body := bytes.slice(0, bytes.size() - 4)
	if bytes.slice(bytes.size() - 4) != _checksum(body):
		return _error("checksum", "The share code checksum does not match. Check for a mistyped character.")
	var offset := 0
	var generator := int(body[offset])
	offset += 1
	var expected_generator := V8_GENERATOR_VERSION if schema == V8_SCHEMA_VERSION else GENERATOR_VERSION
	if generator != expected_generator:
		return _error("unsupported_generator", "Circuit generator version %d is not supported by this build." % generator)
	var theme_index := int(body[offset])
	var room_index := int(body[offset + 1])
	var reverse_byte := int(body[offset + 2])
	var danger_level := int(body[offset + 3])
	var tier_index := int(body[offset + 4])
	offset += 5
	if theme_index < 0 or theme_index >= THEMES.size() or room_index < 0 or room_index >= ROOMS.size():
		return _error("invalid_fields", "The share code contains an unknown theme or room.")
	if reverse_byte not in [0, 1] or danger_level < 1 or danger_level > 3:
		return _error("invalid_fields", "The share code contains an invalid direction or danger profile.")
	if tier_index < 0 or tier_index >= GENERATED_RULES.LENGTH_TIERS.size():
		return _error("invalid_fields", "The share code contains an unknown length profile.")
	var room_recipe_id := -1
	var room_recipe_revision := -1
	var room_geometry_seed := -1
	if schema == V8_SCHEMA_VERSION:
		if offset + 6 > body.size():
			return _error("truncated", "The share code is incomplete; room identity data is missing.")
		room_recipe_id = int(body[offset])
		room_recipe_revision = int(body[offset + 1])
		room_geometry_seed = _read_u32(body, offset + 2)
		offset += 6
	var seeds := {}
	for domain: String in DOMAINS:
		if offset + 4 > body.size():
			return _error("truncated", "The share code is incomplete; circuit seeds are missing.")
		seeds[domain] = _read_u32(body, offset)
		offset += 4
	var material_result := _read_short_string(body, offset)
	if not bool(material_result.get("ok", false)):
		return material_result
	offset = int(material_result["offset"])
	var palette_result := _read_short_string(body, offset)
	if not bool(palette_result.get("ok", false)):
		return palette_result
	offset = int(palette_result["offset"])
	if offset != body.size():
		return _error("trailing_data", "The share code contains unexpected trailing data.")
	var identity := _canonical_identity_v8(
		THEMES[theme_index], ROOMS[room_index], reverse_byte == 1, danger_level,
		String(material_result["value"]), String(palette_result["value"]), seeds,
		GENERATED_RULES.LENGTH_TIERS[tier_index], room_recipe_id, room_recipe_revision, room_geometry_seed
	) if schema == V8_SCHEMA_VERSION else _canonical_identity(
		THEMES[theme_index], ROOMS[room_index], reverse_byte == 1, danger_level,
		String(material_result["value"]), String(palette_result["value"]), seeds,
		GENERATED_RULES.LENGTH_TIERS[tier_index]
	)
	if identity.is_empty():
		return _error("invalid_fields", "The share code decoded, but its circuit identity is invalid.")
	return {"ok": true, "identity": identity}


static func room_for_route_seed(seed: int) -> StringName:
	return GENERATED_RULES.room_for_composition_seed(_room_composition_seed_for_route(seed))


static func room_for_composition_seed(seed: int) -> StringName:
	return GENERATED_RULES.room_for_composition_seed(seed)


static func generation_options(identity_value: Variant) -> Dictionary:
	var result := generation_options_result(identity_value)
	return (result.get("options", {}) as Dictionary).duplicate(true) if bool(result.get("ok", false)) else {}


static func generation_options_result(identity_value: Variant) -> Dictionary:
	var normalized := normalize_result(identity_value)
	if not bool(normalized.get("ok", false)):
		return normalized
	var identity: Dictionary = normalized["identity"]
	var options := {
		"schema_version": int(identity["schema_version"]),
		"generator_version": int(identity["generator_version"]),
		"act": int(identity["danger_level"]),
		"length_tier": String(identity["length_tier"]),
		"sub_seeds": (identity["sub_seeds"] as Dictionary).duplicate(true),
		"material_id": String(identity["material_id"]),
		"palette_id": String(identity["palette_id"]),
	}
	if int(identity["schema_version"]) == V8_SCHEMA_VERSION:
		options["room_recipe_id"] = int(identity["room_recipe_id"])
		options["room_recipe_revision"] = int(identity["room_recipe_revision"])
		options["room_geometry_seed"] = int(identity["room_geometry_seed"])
	return {"ok": true, "options": options}


static func _normalize_v8(raw: Dictionary) -> Dictionary:
	if raw.get("theme") is not String or raw.get("room") is not String:
		return _error("invalid_identity", "Circuit identity has an invalid theme or room.")
	if raw.get("reverse") is not bool or raw.get("material_id") is not String or raw.get("palette_id") is not String:
		return _error("invalid_identity", "Circuit identity has invalid direction or material fields.")
	var danger_value: Variant = raw.get("danger_level")
	if (danger_value is not int and danger_value is not float) or float(int(danger_value)) != float(danger_value):
		return _error("invalid_identity", "Circuit identity has an invalid danger level.")
	var seeds: Variant = raw.get("sub_seeds")
	if seeds is not Dictionary:
		return _error("invalid_identity", "Circuit identity is missing its sub-seeds.")
	var length_tier: Variant = raw.get("length_tier")
	if length_tier is not String or not GENERATED_RULES.LENGTH_TIERS.has(length_tier as String):
		return _error("invalid_identity", "Schema 2 circuit identity requires a known length profile.")
	for field: String in ["room_recipe_id", "room_recipe_revision", "room_geometry_seed"]:
		if not raw.has(field) or not _is_integral_number(raw[field]):
			return _error("invalid_identity", "Schema 2 circuit identity is missing %s." % field)
	var canonical := _canonical_identity_v8(
		String(raw["theme"]), String(raw["room"]), bool(raw["reverse"]), int(danger_value),
		String(raw["material_id"]), String(raw["palette_id"]), seeds as Dictionary,
		String(length_tier), int(raw["room_recipe_id"]), int(raw["room_recipe_revision"]),
		int(raw["room_geometry_seed"])
	)
	if canonical.is_empty():
		return _error("invalid_identity", "Schema 2 circuit identity fields are inconsistent.")
	if raw.has("fingerprint") and String(raw["fingerprint"]) != String(canonical["fingerprint"]):
		return _error("fingerprint", "Circuit identity fingerprint does not match its fields.")
	return {"ok": true, "identity": canonical}


static func _version_pair(raw: Dictionary) -> Dictionary:
	if not raw.has("schema_version") or not raw.has("generator_version"):
		return _error("missing_version", "Circuit identity requires explicit schema and generator versions.")
	if not _is_integral_number(raw["schema_version"]) or not _is_integral_number(raw["generator_version"]):
		return _error("invalid_version", "Circuit identity schema and generator versions must be integers.")
	return {
		"ok": true,
		"schema_version": int(raw["schema_version"]),
		"generator_version": int(raw["generator_version"]),
	}


static func _unsupported_version(schema: int, generator: int) -> Dictionary:
	if schema not in [SCHEMA_VERSION, V8_SCHEMA_VERSION]:
		return _error("unsupported_schema", "Circuit identity schema %d is not supported by this build." % schema)
	return _error(
		"unsupported_generator",
		"Circuit generator version %d is not supported for schema %d." % [generator, schema]
	)


static func _canonical_identity_v8(
		theme: String,
		room: String,
		reverse: bool,
		danger_level: int,
		material_id: String,
		palette_id: String,
		seeds_value: Dictionary,
		length_tier: String,
		room_recipe_id: int,
		room_recipe_revision: int,
		room_geometry_seed: int
) -> Dictionary:
	if not theme in THEMES or not room in ROOMS or danger_level < 1 or danger_level > 3:
		return {}
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return {}
	if not _valid_explicit_id(material_id) or not _valid_explicit_id(palette_id):
		return {}
	if room_recipe_id < 0 or room_recipe_id > 0xFF or room_recipe_revision < 0 or room_recipe_revision > 0xFF:
		return {}
	var recipe: Variant = V8_ROOM_RECIPES.get(room_recipe_id)
	if recipe is not Dictionary or String((recipe as Dictionary).get("family", "")) != room:
		return {}
	if int((recipe as Dictionary).get("revision", -1)) != room_recipe_revision or not _is_seed(room_geometry_seed):
		return {}
	var seeds := {}
	var fingerprints := {}
	for domain: String in DOMAINS:
		var value: Variant = seeds_value.get(domain)
		if not _is_seed(value):
			return {}
		var seed := int(value)
		seeds[domain] = seed
		fingerprints[domain] = _domain_fingerprint_v8(domain, seed)
	if String(GENERATED_RULES.room_for_composition_seed(int(seeds["room_composition"]))) != room:
		return {}
	var story_id := String(GENERATED_RULES.story_id(StringName(theme), int(seeds["dressing"])))
	var resolved := WORLD_MATERIALS.resolve(StringName(theme), StringName(story_id), int(seeds["material"]), material_id, palette_id)
	material_id = String(resolved["material_id"])
	palette_id = String(resolved["palette_id"])
	var identity := {
		"schema_version": V8_SCHEMA_VERSION,
		"generator_version": V8_GENERATOR_VERSION,
		"theme": theme,
		"room": room,
		"reverse": reverse,
		"danger_level": danger_level,
		"length_tier": length_tier,
		"room_recipe_id": room_recipe_id,
		"room_recipe_revision": room_recipe_revision,
		"room_geometry_seed": room_geometry_seed,
		"material_id": material_id,
		"palette_id": palette_id,
		"material_fallback_id": "base-%03d" % posmod(int(seeds["material"]), 1000),
		"palette_fallback_id": "%s-default-%02d" % [theme, posmod(int(seeds["material"]) / 1000, 32)],
		"story_id": story_id,
		"danger_profile": GENERATED_RULES.danger_profile(danger_level, int(seeds["obstacle"]), int(seeds["hazard"])),
		"sub_seeds": seeds,
		"fingerprints": fingerprints,
	}
	fingerprints["circuit"] = _circuit_fingerprint_v8(identity, false)
	identity["fingerprint"] = _circuit_fingerprint_v8(identity, true)
	identity["display_name"] = _build_display_name(identity)
	identity["summary"] = _build_summary(identity)
	return identity


static func _canonical_identity(theme: String, room: String, reverse: bool, danger_level: int, material_id: String, palette_id: String, seeds_value: Dictionary, length_tier: String = "standard") -> Dictionary:
	if not theme in THEMES or not room in ROOMS or danger_level < 1 or danger_level > 3:
		return {}
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return {}
	if not _valid_explicit_id(material_id) or not _valid_explicit_id(palette_id):
		return {}
	var seeds := {}
	var fingerprints := {}
	for domain: String in DOMAINS:
		var value: Variant = seeds_value.get(domain)
		if not _is_seed(value):
			return {}
		var seed := int(value)
		seeds[domain] = seed
		fingerprints[domain] = _domain_fingerprint(domain, seed)
	if String(GENERATED_RULES.room_for_composition_seed(int(seeds["room_composition"]))) != room:
		return {}
	var story_id := String(GENERATED_RULES.story_id(StringName(theme), int(seeds["dressing"])))
	var resolved := WORLD_MATERIALS.resolve(StringName(theme), StringName(story_id), int(seeds["material"]), material_id, palette_id)
	material_id = String(resolved["material_id"])
	palette_id = String(resolved["palette_id"])
	var material_fallback := "base-%03d" % posmod(int(seeds["material"]), 1000)
	var palette_fallback := "%s-default-%02d" % [theme, posmod(int(seeds["material"]) / 1000, 32)]
	var danger := GENERATED_RULES.danger_profile(danger_level, int(seeds["obstacle"]), int(seeds["hazard"]))
	var identity := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"theme": theme,
		"room": room,
		"reverse": reverse,
		"danger_level": danger_level,
		"length_tier": length_tier,
		"material_id": material_id,
		"palette_id": palette_id,
		"material_fallback_id": material_fallback,
		"palette_fallback_id": palette_fallback,
		"story_id": story_id,
		"danger_profile": danger,
		"sub_seeds": seeds,
		"fingerprints": fingerprints,
	}
	fingerprints["circuit"] = _circuit_fingerprint(identity, false)
	identity["fingerprint"] = _circuit_fingerprint(identity, true)
	identity["display_name"] = _build_display_name(identity)
	identity["summary"] = _build_summary(identity)
	return identity


static func _build_display_name(identity: Dictionary) -> String:
	var seed := int(identity["sub_seeds"]["route"])
	var nouns: Array = THEME_NOUNS[String(identity["theme"])]
	var adjective := String(NAME_ADJECTIVES[posmod(seed, NAME_ADJECTIVES.size())])
	var noun := String(nouns[posmod(seed / NAME_ADJECTIVES.size(), nouns.size())])
	return "%s %s Circuit" % [adjective, noun]


static func _build_summary(identity: Dictionary) -> String:
	var seeds: Dictionary = identity["sub_seeds"]
	var material := String(identity["material_id"])
	if material.is_empty():
		material = "fallback %s" % String(identity["material_fallback_id"])
	var palette := String(identity["palette_id"])
	if palette.is_empty():
		palette = "fallback %s" % String(identity["palette_fallback_id"])
	var danger: Dictionary = identity["danger_profile"]
	var obstacle_count := int(danger["obstacle_count"])
	var obstacle_text := "no static obstacles" if obstacle_count == 0 else "up to %d static obstacle%s" % [obstacle_count, "" if obstacle_count == 1 else "s"]
	var danger_text := "%s · %s" % [obstacle_text, "moving hazard" if bool(danger["hazard_present"]) else "no moving hazard"]
	return "Seed %d · Route %s · %s · %s room / %s · Material %s / palette %s · %s · %s" % [
		int(seeds["route"]),
		String(identity["fingerprints"]["route"]).substr(0, 8).to_upper(),
		String(identity["theme"]).capitalize(),
		String(identity["room"]).capitalize(),
		String(identity["story_id"]).replace("_", " ").capitalize(),
		material,
		palette,
		"Reverse" if bool(identity["reverse"]) else "Forward",
		danger_text,
	]


static func _domain_fingerprint(domain: String, seed: int) -> String:
	return ("pc-generated-domain-v%d|%s|%d" % [GENERATOR_VERSION, domain, seed]).sha256_text().substr(0, 16)


static func _circuit_fingerprint(identity: Dictionary, include_direction: bool) -> String:
	var parts := PackedStringArray([
		"pc-generated-circuit-v%d" % GENERATOR_VERSION,
		String(identity["theme"]),
		String(identity["room"]),
		str(identity["danger_level"]),
		String(identity["length_tier"]),
		String(identity["material_id"]),
		String(identity["palette_id"]),
	])
	if include_direction:
		parts.append("reverse=%s" % str(identity["reverse"]))
	var seeds: Dictionary = identity["sub_seeds"]
	for domain: String in DOMAINS:
		parts.append("%s=%d" % [domain, int(seeds[domain])])
	return "|".join(parts).sha256_text().substr(0, 16)


static func _domain_fingerprint_v8(domain: String, seed: int) -> String:
	return ("pc-generated-domain-v8|%s|%d" % [domain, seed]).sha256_text().substr(0, 16)


static func _circuit_fingerprint_v8(identity: Dictionary, include_direction: bool) -> String:
	var parts := PackedStringArray([
		"pc-generated-circuit-schema2-v8",
		String(identity["theme"]),
		String(identity["room"]),
		str(identity["room_recipe_id"]),
		str(identity["room_recipe_revision"]),
		str(identity["room_geometry_seed"]),
		str(identity["danger_level"]),
		String(identity["length_tier"]),
		String(identity["material_id"]),
		String(identity["palette_id"]),
	])
	if include_direction:
		parts.append("reverse=%s" % str(identity["reverse"]))
	var seeds: Dictionary = identity["sub_seeds"]
	for domain: String in DOMAINS:
		parts.append("%s=%d" % [domain, int(seeds[domain])])
	return "|".join(parts).sha256_text().substr(0, 16)


static func _v8_room_geometry_seed(room_composition_seed: int, recipe_id: int, recipe_revision: int) -> int:
	var bytes := PackedByteArray()
	_append_length_prefixed_utf8(bytes, "pocket-circuit")
	_append_length_prefixed_utf8(bytes, "v8-room-geometry")
	_append_u32(bytes, V8_GENERATOR_VERSION)
	_append_u32(bytes, room_composition_seed)
	_append_u32(bytes, recipe_id)
	_append_u32(bytes, recipe_revision)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var digest := context.finish()
	return _read_u32(digest, 0) & MAX_SEED


static func _mix_seed(seed: int, stream: String) -> int:
	var value := (seed ^ int(stream.hash()) ^ 0x6D2B79F5) & MAX_SEED
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & MAX_SEED
	value = ((value ^ (value >> 15)) * 0x45D9F3B) & MAX_SEED
	return (value ^ (value >> 16)) & MAX_SEED


static func _room_composition_seed_for_route(seed: int) -> int:
	return ((seed * 1103515245 + 12345) ^ (seed << 7)) & MAX_SEED


static func _room_composition_seed_for_room(route_seed: int, room: String) -> int:
	var seed := _room_composition_seed_for_route(route_seed)
	var room_index := ROOMS.find(room)
	var delta := posmod(room_index - posmod(seed, ROOMS.size()), ROOMS.size())
	if seed > MAX_SEED - delta:
		seed -= ROOMS.size()
	return seed + delta


static func _is_seed(value: Variant) -> bool:
	if value is not int and value is not float:
		return false
	var seed := int(value)
	return seed >= 0 and seed <= MAX_SEED and float(seed) == float(value)


static func _is_integral_number(value: Variant) -> bool:
	return (value is int or value is float) and float(int(value)) == float(value)


static func _valid_explicit_id(value: String) -> bool:
	if value.is_empty():
		return true
	if value.length() > MAX_EXPLICIT_ID_LENGTH:
		return false
	for character: String in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return value == value.to_lower()


static func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xFF)
	bytes.append((value >> 16) & 0xFF)
	bytes.append((value >> 8) & 0xFF)
	bytes.append(value & 0xFF)


static func _append_u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 8) & 0xFF)
	bytes.append(value & 0xFF)


static func _append_length_prefixed_utf8(bytes: PackedByteArray, value: String) -> void:
	var encoded := value.to_utf8_buffer()
	_append_u16(bytes, encoded.size())
	bytes.append_array(encoded)


static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


static func _append_short_string(bytes: PackedByteArray, value: String) -> void:
	var encoded := value.to_utf8_buffer()
	bytes.append(encoded.size())
	bytes.append_array(encoded)


static func _read_short_string(bytes: PackedByteArray, offset: int) -> Dictionary:
	if offset >= bytes.size():
		return _error("truncated", "The share code is missing identity data.")
	var length := int(bytes[offset])
	offset += 1
	if length > MAX_EXPLICIT_ID_LENGTH or offset + length > bytes.size():
		return _error("invalid_fields", "The share code contains an invalid material or palette identifier.")
	return {"ok": true, "value": bytes.slice(offset, offset + length).get_string_from_utf8(), "offset": offset + length}


static func _checksum(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().slice(0, 4)


static func _base32_encode(bytes: PackedByteArray) -> String:
	var output := ""
	var buffer := 0
	var bits := 0
	for byte: int in bytes:
		buffer = (buffer << 8) | byte
		bits += 8
		while bits >= 5:
			bits -= 5
			output += SHARE_ALPHABET[(buffer >> bits) & 31]
		buffer &= (1 << bits) - 1 if bits > 0 else 0
	if bits > 0:
		output += SHARE_ALPHABET[(buffer << (5 - bits)) & 31]
	return output


static func _base32_decode(text: String) -> Dictionary:
	if text.is_empty():
		return _error("truncated", "The share code has no payload.")
	var bytes := PackedByteArray()
	var buffer := 0
	var bits := 0
	for raw_character: String in text:
		var character := raw_character
		if character == "O":
			character = "0"
		elif character in ["I", "L"]:
			character = "1"
		var value := SHARE_ALPHABET.find(character)
		if value < 0:
			return _error("character", "The share code contains '%s', which is not a valid code character." % raw_character)
		buffer = (buffer << 5) | value
		bits += 5
		if bits >= 8:
			bits -= 8
			bytes.append((buffer >> bits) & 0xFF)
			buffer &= (1 << bits) - 1 if bits > 0 else 0
	if bits > 0 and buffer != 0:
		return _error("padding", "The share code has invalid trailing bits; check the final character.")
	return {"ok": true, "bytes": bytes}


static func _group_code(compact: String) -> String:
	var output := compact.substr(0, SHARE_PREFIX.length())
	var payload := compact.substr(SHARE_PREFIX.length())
	for offset in range(0, payload.length(), 5):
		output += "-" + payload.substr(offset, 5)
	return output


static func _error(kind: String, message: String) -> Dictionary:
	return {"ok": false, "kind": kind, "error": message}
