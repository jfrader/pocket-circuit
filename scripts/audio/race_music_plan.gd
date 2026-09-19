extends RefCounted

## Deterministic music direction for Pocket Circuit.
##
## The live Gamestruments score is regenerated per circuit from a seed derived
## from the track identity, so the same circuit always produces the same music
## while different circuits sound different. This module owns the mapping from
## track identity to generate seed, instrument/energy profile, and the phase
## deck the race rotates through so no one section holds.

const THEME_STYLES := {
	"kitchen": ["funk", "fusion", "chip"],
	"workshop": ["fusion", "neon", "chip"],
	"office": ["neon", "fusion", "chip"],
}
const FALLBACK_STYLES: Array[String] = ["funk", "fusion", "neon", "chip"]

const TIER_ORDER: Array[String] = ["compact", "standard", "long", "endurance", "marathon"]
const TIER_TRAITS := {
	"compact": {"energy": 0.54, "complexity": 0.50},
	"standard": {"energy": 0.62, "complexity": 0.60},
	"long": {"energy": 0.70, "complexity": 0.67},
	"endurance": {"energy": 0.79, "complexity": 0.73},
	"marathon": {"energy": 0.89, "complexity": 0.80},
}
const GROOVES: Array[String] = ["cruise", "slipstream"]
const PEAKS: Array[String] = ["redline", "attack"]
const MENU_STYLE := "funk"
const MENU_PROFILE := {
	"style": MENU_STYLE,
	"energy": 0.42,
	"complexity": 0.52,
	"brightness": 0.60,
	"syncopation": 0.50,
}
const MENU_DECK: Array[String] = ["garage", "breather", "cruise", "breather"]


## The Gamestruments generate seed for a circuit. The whole track identity
## feeds it, so a mirrored or retiered layout is a different track with its
## own score while replays of the same circuit reproduce the same music.
static func seed_for_event(event: Dictionary) -> String:
	var direction := "rev" if bool(event.get("reverse", false)) else "fwd"
	return "pc_%s_%s_%d_%s_%s" % [
		_text(event.get("theme", "kitchen")),
		_text(event.get("room", "classic")),
		int(event.get("seed", 0)),
		direction,
		_tier(event),
	]


## Style, tempo/timbre and energy knobs for a circuit. Style cycles through the
## theme's palette by route seed; traits rise with the length tier and darken
## with the act so danger level is audible.
static func race_profile(event: Dictionary) -> Dictionary:
	var styles: Array = THEME_STYLES.get(_text(event.get("theme", "kitchen")), FALLBACK_STYLES)
	var route := int(event.get("seed", 0))
	var rank := _tier_rank(_tier(event))
	var traits: Dictionary = TIER_TRAITS.get(_tier(event), TIER_TRAITS["standard"])
	var act := clampi(int(event.get("act", 1)), 1, 3)
	return {
		"style": String(styles[posmod(route, styles.size())]),
		"energy": clampf(float(traits["energy"]) + float(posmod(route, 5)) * 0.012, 0.0, 1.0),
		"complexity": clampf(float(traits["complexity"]) + float(posmod(route, 7)) * 0.01, 0.0, 1.0),
		"brightness": clampf(0.62 - float(act - 1) * 0.10, 0.0, 1.0),
		"syncopation": clampf(0.50 + float(rank) * 0.04 + float(posmod(route, 3)) * 0.01, 0.0, 1.0),
	}


## The groove/peak running order for a circuit: more peaks as the tier grows,
## deterministic per track so the same seed always plays the same arc.
static func flow_deck(event: Dictionary) -> Array[String]:
	var rank := _tier_rank(_tier(event))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_for_event(event).hash())
	var groove_count := 3 + int((rank + 1) / 2)
	var peak_count := 2 + rank
	var deck: Array[String] = []
	for index in maxi(groove_count, peak_count):
		if index < groove_count:
			deck.append(GROOVES[rng.randi_range(0, GROOVES.size() - 1)])
		if index < peak_count:
			deck.append(PEAKS[rng.randi_range(0, PEAKS.size() - 1)])
	if deck.is_empty() or not GROOVES.has(deck[0]):
		deck.insert(0, GROOVES[0])
	return deck


## Seconds a phase holds before the rotation steps on. Longer circuits hold
## each phase longer so the whole race still travels the deck.
static func tier_dwell(tier: String) -> float:
	match tier:
		"compact":
			return 9.0
		"long":
			return 13.0
		"endurance":
			return 15.0
		"marathon":
			return 17.0
	return 11.0


static func menu_profile() -> Dictionary:
	return MENU_PROFILE.duplicate()


static func menu_deck() -> Array[String]:
	var deck: Array[String] = []
	deck.assign(MENU_DECK)
	return deck


static func _tier(event: Dictionary) -> String:
	var tier := _text(event.get("length_tier", "standard"))
	return tier if TIER_ORDER.has(tier) else "standard"


static func _tier_rank(tier: String) -> int:
	return maxi(0, TIER_ORDER.find(tier))


static func _text(value: Variant) -> String:
	return String(value) if value != null else ""
