extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/progression/championship_circuit_identity.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const FIXTURE_SEED := 123456789


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var championship := IDENTITIES.create_championship(FIXTURE_SEED)
	if not _expect(championship == IDENTITIES.create_championship(FIXTURE_SEED), "the same championship seed should reproduce every event identity exactly"):
		return
	if not _expect(int(championship["schema_version"]) == 1 and int(championship["generator_version"]) == 11, "championship identity should carry schema and generator versions"):
		return
	if not _expect(String(championship["fingerprint"]) == "75cd1bc71e79e3e3", "the deterministic championship fingerprint must stay regression-pinned"):
		return
	var events: Dictionary = championship["events"]
	if not _expect(events.size() == CATALOG.EVENTS.size(), "every catalog event should receive one stable identity"):
		return

	var circuit_fingerprints := {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var identity: Dictionary = events[event_id]
		var sub_seeds: Dictionary = identity["sub_seeds"]
		var fingerprints: Dictionary = identity["fingerprints"]
		if not _expect(int(identity["schema_version"]) == 1 and int(identity["generator_version"]) == 11, "%s should carry record versions" % event_id):
			return
		if not _expect(sub_seeds.keys().size() == IDENTITIES.DOMAINS.size(), "%s should expose every domain-separated sub-seed" % event_id):
			return
		for domain: String in IDENTITIES.DOMAINS:
			if not _expect(sub_seeds.has(domain) and fingerprints.has(domain) and String(fingerprints[domain]).length() == 16, "%s should expose inspectable %s metadata" % [event_id, domain]):
				return
		var circuit_fingerprint := String(fingerprints.get("circuit", ""))
		if not _expect(circuit_fingerprint.length() == 16 and not circuit_fingerprints.has(circuit_fingerprint), "%s should have a distinct inspectable circuit fingerprint" % event_id):
			return
		circuit_fingerprints[circuit_fingerprint] = true
		var prepared := TRACK_BUILDER.prepare_layout(StringName(identity["theme"]), StringName(identity["room"]), int(sub_seeds["route"]))
		if not _expect(not prepared.is_empty() and int(prepared["spec"]["requested_seed"]) == int(sub_seeds["route"]), "%s should resolve its identity to a legal route without seed walking" % event_id):
			return

	var crumb_rush: Dictionary = events["kitchen_crumb_rush"]
	if not _expect(
			crumb_rush["room"] == "tall"
			and crumb_rush["sub_seeds"] == {
				"route": 721039,
				"room_composition": 710912,
				"material": 763768,
				"dressing": 852422,
				"obstacle": 308711,
				"hazard": 806213,
			}
			and String(crumb_rush["fingerprints"]["circuit"]) == "64b580c5eda27188",
			"a representative event should keep its pinned route, room, future-system seeds, and fingerprint"
	):
		return

	var reverse_event := CATALOG.get_event("kitchen_mug_run")
	var forward_copy := reverse_event.duplicate(true)
	forward_copy["reverse"] = false
	if not _expect(IDENTITIES.create_event(FIXTURE_SEED, reverse_event) == IDENTITIES.create_event(FIXTURE_SEED, forward_copy), "race direction must not alter a circuit identity"):
		return
	var applied := IDENTITIES.apply_to_event(reverse_event, events["kitchen_mug_run"])
	if not _expect(
			bool(applied["reverse"])
			and int(applied["seed"]) == int(events["kitchen_mug_run"]["sub_seeds"]["route"])
			and String(applied["room"]) == String(events["kitchen_mug_run"]["room"])
			and applied["circuit_identity"] == events["kitchen_mug_run"]
			and applied["generated_circuit_identity"]["sub_seeds"] == events["kitchen_mug_run"]["sub_seeds"]
			and bool(applied["generated_circuit_identity"]["reverse"])
			and String(applied["circuit_display_name"]).contains("Circuit")
			and String(applied["circuit_summary"]).contains("Material ")
			and not String(applied["circuit_summary"]).contains("Material fallback"),
			"applying identity should preserve event rules while exposing generator metadata"
	):
		return

	var corrupted := championship.duplicate(true)
	corrupted["events"]["kitchen_crumb_rush"]["sub_seeds"]["hazard"] = 42
	if not _expect(IDENTITIES.normalize_championship(corrupted) == championship, "normalization should deterministically repair a record whose fingerprint no longer matches"):
		return
	if not _expect(IDENTITIES.create_championship(FIXTURE_SEED + 1)["fingerprint"] != championship["fingerprint"], "a different championship seed should produce a different circuit set"):
		return

	# An older record (generator_version=1) keeps its master seed while its
	# fingerprints advance, so old-geometry identities no longer compare as the
	# current circuit.
	var legacy := {
		"schema_version": 1,
		"generator_version": 1,
		"seed": FIXTURE_SEED,
		"events": {},
		"fingerprint": "ba391b90f4c3f2b5",
	}
	var migrated := IDENTITIES.normalize_championship(legacy)
	if not _expect(int(migrated["seed"]) == FIXTURE_SEED and int(migrated["generator_version"]) == 11 and String(migrated["fingerprint"]) != "ba391b90f4c3f2b5", "normalizing an older championship should preserve the master seed while advancing the generator version and fingerprints"):
		return
	var previous := championship.duplicate(true)
	previous["generator_version"] = 10
	previous["fingerprint"] = "b22d4390d2e65a14"
	if not _expect(IDENTITIES.normalize_championship(previous) == championship, "a version-10 championship should advance its identity while retaining the same seeded event set"):
		return

	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available for championship session integration"):
		return
	var progress: Dictionary = app.call("get_save_data")
	progress["championship_started"] = true
	progress["championship_circuit"] = championship
	app.set("_save_data", progress)
	app.call("start_race", "kitchen_crumb_rush", "rustbug", false)
	var session: Dictionary = app.call("get_current_race_session")
	var session_event: Dictionary = session.get("event", {})
	if not _expect(
			String(session.get("mode", "")) == "championship"
			and session_event.get("circuit_identity", {}) == crumb_rush
			and int(session_event.get("seed", -1)) == 721039
			and String(session_event.get("room", "")) == "tall"
			and String(session_event.get("circuit_fingerprint", "")) == "64b580c5eda27188",
			"starting a championship race should resolve the persisted identity instead of drawing a new circuit"
	):
		return

	print("CHAMPIONSHIP_CIRCUIT_IDENTITY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CHAMPIONSHIP_CIRCUIT_IDENTITY_TEST FAIL: " + message)
	quit(1)
	return false
