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
const BUILDS: Array[String] = ["ignition", "grid"]
const PEAKS: Array[String] = ["redline", "attack"]
const CALMS: Array[String] = ["breather"]
const MENU_STYLE := "funk"
const MENU_PROFILE := {
	"style": MENU_STYLE,
	"energy": 0.32,
	"complexity": 0.52,
	"brightness": 0.60,
	"syncopation": 0.50,
}
## One 4-bar phrase at a mid racing tempo. Repeated deck slots hold a phase
## through several loops without cueing it again.
const MENU_PHRASE_SECONDS := 7.5
const MENU_GRID_LOOPS := 4


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


## Running order for a circuit. Grooves, builds, peaks, and a breather, more of
## each as the tier grows. Deterministic per track. Opens on a groove.
static func flow_deck(event: Dictionary) -> Array[String]:
	var rank := _tier_rank(_tier(event))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_for_event(event).hash())
	var deck: Array[String] = []
	for _cycle in 1 + rank:
		deck.append(_pick_next(GROOVES, deck, rng))
		deck.append(_pick_next(BUILDS, deck, rng))
		deck.append(_pick_next(PEAKS, deck, rng))
		deck.append(_pick_next(CALMS, deck, rng))
		deck.append(_pick_next(GROOVES, deck, rng))
		deck.append(_pick_next(PEAKS, deck, rng))
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


## Grid loops several times, then a groove that can keep going. Ignition is not
## in this cycle: cueing it replays its slow opening.
static func menu_deck() -> Array[String]:
	var deck: Array[String] = []
	var visits: Array[String] = ["cruise", "breather", "slipstream"]
	for visit in visits:
		_append_loops(deck, "grid", MENU_GRID_LOOPS)
		_append_loops(deck, visit, 4 if visit == "slipstream" else 2)
	return deck


static func menu_phrase_seconds() -> float:
	return MENU_PHRASE_SECONDS


static func _append_loops(deck: Array[String], section: String, count: int) -> void:
	for _index in count:
		deck.append(section)


static func _pick_next(options: Array[String], deck: Array[String], rng: RandomNumberGenerator) -> String:
	var previous := ""
	if not deck.is_empty():
		previous = deck[deck.size() - 1]
	var choice := options[rng.randi_range(0, options.size() - 1)]
	if options.size() > 1 and choice == previous:
		choice = options[(options.find(choice) + 1) % options.size()]
	return choice


static func _tier(event: Dictionary) -> String:
	var tier := _text(event.get("length_tier", "standard"))
	return tier if TIER_ORDER.has(tier) else "standard"


static func _tier_rank(tier: String) -> int:
	return maxi(0, TIER_ORDER.find(tier))


static func _text(value: Variant) -> String:
	return String(value) if value != null else ""
