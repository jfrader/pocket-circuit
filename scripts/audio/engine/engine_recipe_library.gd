class_name EngineRecipeLibrary
extends RefCounted

## Resolves a vehicle's engine voice. A hand-authored recipe wins; everything
## else derives deterministically from VehicleStats, so a new car is audible the
## day it is added and a tuning change is a one-file override.

const RECIPE_PATHS := {
	"rustbug": "res://data/audio/engine_recipes/rustbug.tres",
}
## Used when a car reaches the audio layer without an identity: the recipe still
## derives a valid voice from its stats instead of dropping to the legacy loop.
const UNIDENTIFIED_VEHICLE_ID := "unidentified"


static func resolve(vehicle_id: String, stats: VehicleStats) -> EngineRecipe:
	var path := String(RECIPE_PATHS.get(vehicle_id, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var authored := load(path) as EngineRecipe
		if authored != null and authored.is_valid():
			return authored
		push_warning("Engine recipe override for %s is missing or invalid; deriving from stats" % vehicle_id)
	return EngineRecipe.from_vehicle(vehicle_id, stats)


## Vehicle id for a stats resource, used when the caller has no id at hand.
## Derived from the resource file name, which the catalog owns.
static func vehicle_id_for(stats: VehicleStats) -> String:
	if stats == null:
		return ""
	return stats.resource_path.get_file().get_basename()
