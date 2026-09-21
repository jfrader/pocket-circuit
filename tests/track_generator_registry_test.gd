extends SceneTree

const REGISTRY := preload("res://scripts/race/track_generator_registry.gd")
const FAILING_V8 := preload("res://tests/support/failing_v8_track_generator.gd")

var legacy_calls := 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var default_selection := REGISTRY.resolve_options({})
	if not _expect(bool(default_selection.get("ok", false)) and default_selection.get("path") == REGISTRY.LEGACY_PATH and bool(default_selection.get("used_legacy_default", false)), "unversioned legacy APIs should keep their explicit v7 default"):
		return
	var legacy_selection := REGISTRY.resolve_options({"schema_version": 1, "generator_version": 7})
	if not _expect(bool(legacy_selection.get("ok", false)) and legacy_selection.get("path") == REGISTRY.LEGACY_PATH and not bool(legacy_selection.get("used_legacy_default", true)), "schema 1 generator 7 should select only the frozen legacy path"):
		return
	var missing_pair := REGISTRY.resolve_options({"generator_version": 7})
	if not _expect(missing_pair.get("kind") == "missing_version" and String(missing_pair.get("error", "")).contains("together"), "partial version requests should fail explicitly"):
		return
	for unsupported: Dictionary in [
		{"schema_version": 1, "generator_version": 6},
		{"schema_version": 1, "generator_version": 5},
		{"schema_version": 9, "generator_version": 8},
	]:
		var result := REGISTRY.resolve_options(unsupported)
		if not _expect(not bool(result.get("ok", false)) and String(result.get("kind", "")).begins_with("unsupported_") and not String(result.get("error", "")).is_empty(), "unsupported request %s should return a specific error" % unsupported):
			return
	var v8_request := {"identity": "fixture"}
	var v8_result := REGISTRY.dispatch(
		{"schema_version": 2, "generator_version": 8},
		v8_request,
		Callable(self, "_legacy_generator"),
		Callable(FAILING_V8, "generate")
	)
	if not _expect(v8_result.get("kind") == "v8_not_implemented" and legacy_calls == 0 and v8_result.get("request") == v8_request, "an explicit v8 request should reach only the test stub and must never fall back to v7"):
		return
	var unavailable := REGISTRY.dispatch({"schema_version": 2, "generator_version": 8}, {}, Callable(self, "_legacy_generator"))
	if not _expect(unavailable.get("kind") == "generator_unavailable" and String(unavailable.get("error", "")).contains("schema 2 version 8") and legacy_calls == 0, "production v8 dispatch should fail clearly until its generator exists"):
		return
	print("TRACK_GENERATOR_REGISTRY_TEST PASS")
	quit(0)


func _legacy_generator(_request: Dictionary) -> Dictionary:
	legacy_calls += 1
	return {"ok": true}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_GENERATOR_REGISTRY_TEST FAIL: " + message)
	quit(1)
	return false
