
extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const SEEDS: Array[int] = [1, 7, 42, 663, 24680, 999999]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var checked := 0
	for theme: StringName in THEMES:
		for danger_level in range(1, 4):
			for seed: int in SEEDS:
				var room := IDENTITIES.room_for_route_seed(seed)
				var identity := IDENTITIES.create(theme, room, seed, false, danger_level)
				var prepared := TRACK_BUILDER.prepare_layout(theme, room, seed, IDENTITIES.generation_options(identity))
				if not _expect(not identity.is_empty() and not prepared.is_empty(), "identity and prepared plan should exist for %s act %d seed %d" % [theme, danger_level, seed]):
					return
				var spec: Dictionary = prepared["spec"]
				var danger: Dictionary = identity["danger_profile"]
				var obstacle_count := (spec.get("obstacle_plan", []) as Array).size()
				var hazard: Dictionary = spec.get("hazard_plan", {})
				var story_text := String(spec["story_id"]).replace("_", " ").capitalize()
				var obstacle_target := int(danger["obstacle_count"])
				var obstacle_text := "no static obstacles" if obstacle_target == 0 else "up to %d static obstacle%s" % [obstacle_target, "" if obstacle_target == 1 else "s"]
				if not _expect(
					String(identity["story_id"]) == String(spec["story_id"])
					and obstacle_count <= obstacle_target
					and bool(danger["hazard_present"]) == bool(hazard.get("present", false))
					and is_equal_approx(float(danger["hazard_chance"]), float(hazard.get("presence_chance", -1.0)))
					and String(identity["summary"]).contains(story_text)
					and String(identity["summary"]).contains(obstacle_text)
					and String(identity["summary"]).contains("moving hazard" if bool(hazard.get("present", false)) else "no moving hazard"),
					"summary story and danger must exactly match prepared %s act %d seed %d" % [theme, danger_level, seed]
				):
					return
				checked += 1
	print("GENERATED_CIRCUIT_SUMMARY_PARITY_TEST PASS cases=%d" % checked)
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_CIRCUIT_SUMMARY_PARITY_TEST FAIL: " + message)
	quit(1)
	return false
