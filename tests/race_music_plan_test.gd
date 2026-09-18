extends SceneTree

## Pure plan test for the per-circuit music direction: the seed is derived from
## the whole track identity, the profile stays inside the library's ranges, and
## each circuit gets a deterministic, legal phase deck that grows with the tier.

const RaceMusicPlan := preload("res://scripts/audio/race_music_plan.gd")

const VALID_STYLES: Array[String] = ["fusion", "neon", "funk", "chip"]
const VALID_PHASES: Array[String] = [
	"garage", "ignition", "grid", "breather", "cruise", "slipstream", "attack",
	"redline", "final-lap", "victory", "cooldown", "defeat", "recovery", "wrong-way",
]


func _initialize() -> void:
	var failures := PackedStringArray()
	var base := {
		"theme": "kitchen", "room": "classic", "seed": 4242, "length_tier": "standard", "act": 1,
	}

	if RaceMusicPlan.seed_for_event(base) != RaceMusicPlan.seed_for_event(base.duplicate()):
		failures.append("seed_for_event must be deterministic")

	for key: String in ["theme", "room", "seed", "length_tier", "reverse"]:
		var changed := base.duplicate()
		match key:
			"theme":
				changed["theme"] = "workshop"
			"room":
				changed["room"] = "wide"
			"seed":
				changed["seed"] = 4243
			"length_tier":
				changed["length_tier"] = "long"
			"reverse":
				changed["reverse"] = true
		if RaceMusicPlan.seed_for_event(changed) == RaceMusicPlan.seed_for_event(base):
			failures.append("seed_for_event must change with " + key)

	var profile := RaceMusicPlan.race_profile(base)
	if not VALID_STYLES.has(String(profile["style"])):
		failures.append("race_profile style must be a library style")
	for key: String in ["energy", "complexity", "brightness", "syncopation"]:
		var value := float(profile[key])
		if value < 0.0 or value > 1.0:
			failures.append("race_profile %s out of range: %f" % [key, value])

	var deck := RaceMusicPlan.flow_deck(base)
	if deck != RaceMusicPlan.flow_deck(base):
		failures.append("flow_deck must be deterministic per track")
	if deck.is_empty() or not ["cruise", "slipstream"].has(deck[0]):
		failures.append("flow_deck must open on a groove")
	var saw_peak := false
	for phase: String in deck:
		if not VALID_PHASES.has(phase):
			failures.append("flow_deck has an invalid phase: " + phase)
		if ["attack", "redline"].has(phase):
			saw_peak = true
	if not saw_peak:
		failures.append("flow_deck must include a peak")

	var compact := base.duplicate()
	compact["length_tier"] = "compact"
	var marathon := base.duplicate()
	marathon["length_tier"] = "marathon"
	if RaceMusicPlan.flow_deck(marathon).size() <= RaceMusicPlan.flow_deck(compact).size():
		failures.append("a marathon deck should be longer than a compact deck")
	if RaceMusicPlan.tier_dwell("marathon") <= RaceMusicPlan.tier_dwell("compact"):
		failures.append("a marathon should hold each phase longer than a compact")

	if not VALID_STYLES.has(String(RaceMusicPlan.menu_profile()["style"])):
		failures.append("menu_profile style must be a library style")
	if RaceMusicPlan.menu_deck().is_empty():
		failures.append("menu_deck must not be empty")

	if not failures.is_empty():
		push_error("RACE_MUSIC_PLAN_TEST FAIL: " + "; ".join(failures))
		quit(1)
		return
	print("RACE_MUSIC_PLAN_TEST PASS")
	quit(0)
