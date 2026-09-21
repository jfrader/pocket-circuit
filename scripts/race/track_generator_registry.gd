class_name TrackGeneratorRegistry
extends RefCounted

const LEGACY_SCHEMA := 1
const LEGACY_GENERATOR := 7
const V8_SCHEMA := 2
const V8_GENERATOR := 8
const LEGACY_PATH := &"legacy_v7"
const V8_PATH := &"v8"

const GENERATORS := {
	"1:7": LEGACY_PATH,
	"2:8": V8_PATH,
}


static func resolve_options(options_value: Variant, default_to_legacy: bool = true) -> Dictionary:
	if options_value is not Dictionary:
		return _error("invalid_options", "Track generation options must be a dictionary.")
	var options := options_value as Dictionary
	if options.has("version_error"):
		return _error("invalid_identity", String(options["version_error"]))
	var has_schema := options.has("schema_version")
	var has_generator := options.has("generator_version")
	if not has_schema and not has_generator:
		if not default_to_legacy:
			return _error("missing_version", "Versioned track generation requires explicit schema and generator versions.")
		return _selection(LEGACY_SCHEMA, LEGACY_GENERATOR, LEGACY_PATH, true)
	if not has_schema or not has_generator:
		return _error("missing_version", "Track generation requires schema_version and generator_version together.")
	if not _is_integral_number(options["schema_version"]) or not _is_integral_number(options["generator_version"]):
		return _error("invalid_version", "Track schema and generator versions must be integers.")
	var schema := int(options["schema_version"])
	var generator := int(options["generator_version"])
	var key := "%d:%d" % [schema, generator]
	if not GENERATORS.has(key):
		if schema not in [LEGACY_SCHEMA, V8_SCHEMA]:
			return _error("unsupported_schema", "Track schema %d is not supported by this build." % schema)
		return _error("unsupported_generator", "Track generator version %d is not supported for schema %d." % [generator, schema])
	return _selection(schema, generator, GENERATORS[key], false)


static func dispatch(
		options_value: Variant,
		request: Dictionary,
		legacy_generator: Callable,
		v8_generator: Callable = Callable(),
		default_to_legacy: bool = true
) -> Dictionary:
	var selection := resolve_options(options_value, default_to_legacy)
	if not bool(selection.get("ok", false)):
		return selection
	var path: StringName = selection["path"]
	var generator := legacy_generator if path == LEGACY_PATH else v8_generator
	if not generator.is_valid():
		return _error(
			"generator_unavailable",
			"Track generator schema %d version %d is recognized but not implemented by this build." % [
				int(selection["schema_version"]), int(selection["generator_version"]),
			]
		)
	var result: Variant = generator.call(request)
	if result is not Dictionary:
		return _error("invalid_generator_result", "Track generator returned an invalid result.")
	return result as Dictionary


static func _selection(schema: int, generator: int, path: StringName, used_default: bool) -> Dictionary:
	return {
		"ok": true,
		"schema_version": schema,
		"generator_version": generator,
		"path": path,
		"used_legacy_default": used_default,
	}


static func _is_integral_number(value: Variant) -> bool:
	return (value is int or value is float) and float(int(value)) == float(value)


static func _error(kind: String, message: String) -> Dictionary:
	return {"ok": false, "kind": kind, "error": message}
