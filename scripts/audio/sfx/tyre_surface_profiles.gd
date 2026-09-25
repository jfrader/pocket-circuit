class_name TyreSurfaceProfiles
extends RefCounted

## Acoustic material profiles for the surfaces defined by the track catalog and
## TrackVariantPresenter. Surface names stay owned by those systems; these rules
## classify their material words instead of maintaining a second surface registry.

const DEFAULT_ID := &"neutral"

const PROFILES := {
	&"polished_wood": {
		"id": &"polished_wood",
		"filter_tilt": 1.0,
		"squeal": 1.0,
		"rumble": 0.65,
		"rattle": 0.05,
	},
	&"workshop_wood": {
		"id": &"workshop_wood",
		"filter_tilt": 0.90,
		"squeal": 0.72,
		"rumble": 1.15,
		"rattle": 0.42,
	},
	&"office_carpet": {
		"id": &"office_carpet",
		"filter_tilt": 0.76,
		"squeal": 0.42,
		"rumble": 1.28,
		"rattle": 0.16,
	},
	&"slick": {
		"id": &"slick",
		"filter_tilt": 1.06,
		"squeal": 1.18,
		"rumble": 0.48,
		"rattle": 0.03,
	},
	&"loose": {
		"id": &"loose",
		"filter_tilt": 0.82,
		"squeal": 0.50,
		"rumble": 1.35,
		"rattle": 0.48,
	},
	DEFAULT_ID: {
		"id": DEFAULT_ID,
		"filter_tilt": 0.95,
		"squeal": 0.82,
		"rumble": 0.90,
		"rattle": 0.14,
	},
}

const BASE_SURFACES := {
	&"polished counter": &"polished_wood",
	&"workbench": &"workshop_wood",
	&"desktop": &"office_carpet",
}

## Ordered by the most specific material. These words come from the canonical
## static and generated surface definitions (spill/oil, paper/dust, metal).
const MATERIAL_RULES := [
	{
		"profile": &"slick",
		"words": ["spill", "oil", "suds", "soap", "syrup", "coffee", "ink", "smear", "polish"],
	},
	{
		"profile": &"office_carpet",
		"words": ["paper", "papers", "keyboard", "desktop", "carpet"],
	},
	{
		"profile": &"loose",
		"words": ["crumb", "biscuit", "dust", "sawdust", "flour", "filings", "eraser"],
	},
	{
		"profile": &"workshop_wood",
		"words": ["workbench", "bench", "spark", "mail shoot"],
	},
]


static func profile_for(surface_name: StringName) -> Dictionary:
	var profile_id: StringName = BASE_SURFACES.get(surface_name, &"")
	if profile_id == &"":
		var normalized := String(surface_name).to_lower()
		for rule: Dictionary in MATERIAL_RULES:
			for word: String in rule["words"]:
				if normalized.contains(word):
					profile_id = rule["profile"]
					break
			if profile_id != &"":
				break
	if profile_id == &"":
		profile_id = DEFAULT_ID
	return (PROFILES[profile_id] as Dictionary).duplicate()


static func profile_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for profile_id: StringName in PROFILES:
		ids.append(profile_id)
	return ids
