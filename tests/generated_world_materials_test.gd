extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const FIXTURE_SEED := 246810


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _expect(MATERIALS.family_count() == 12, "all twelve room-story families should be catalogued"):
		return
	for theme: String in RULES.STORY_IDS.keys():
		var stories: Array = RULES.STORY_IDS[theme]
		if not _expect(stories.size() == 4, "%s should keep four room compositions" % theme):
			return
		var families := {}
		for story_id: String in stories:
			var family_id := MATERIALS.family_id_for_story(StringName(theme), StringName(story_id))
			if not _expect(not family_id.is_empty() and not families.has(family_id), "%s / %s should own a unique material family" % [theme, story_id]):
				return
			families[family_id] = true
			if not _expect(MATERIALS.variant_ids(family_id).size() == 2, "%s should expose two curated palettes" % family_id):
				return
			for palette_id: String in MATERIALS.variant_ids(family_id):
				var resolved := MATERIALS.resolve(StringName(theme), StringName(story_id), 0, family_id, palette_id)
				if not _expect(bool(resolved["known"]), "%s / %s should retain its curated room palette" % [family_id, palette_id]):
					return
				if not _expect(FileAccess.file_exists(String(resolved["floor_texture"])) and FileAccess.file_exists(String(resolved["island_material_texture"])), "%s textures should exist on disk" % family_id):
					return

	var identity := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2)
	if not _expect(String(identity["material_id"]) == "workshop_oiled" and String(identity["palette_id"]) in ["oiled_espresso", "oiled_walnut"] and not String(identity["summary"]).contains("Material fallback"), "default identities should record the catalog material instead of a fallback token"):
		return
	var same := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2)
	if not _expect(same == identity, "material selection must be deterministic"):
		return
	var flipped := IDENTITIES.create(&"workshop", &"wide", FIXTURE_SEED, false, 2, "", "", {"material": int(identity["sub_seeds"]["material"]) + 1})
	if not _expect(String(flipped["material_id"]) == String(identity["material_id"]) and String(flipped["palette_id"]) != String(identity["palette_id"]) and String(flipped["fingerprints"]["route"]) == String(identity["fingerprints"]["route"]), "changing only the material stream should keep geometry fingerprints and swap palette"):
		return

	var options := IDENTITIES.generation_options(identity)
	var prepared := BUILDER.prepare_layout(&"workshop", &"wide", FIXTURE_SEED, options)
	var other_options := options.duplicate(true)
	other_options["material_id"] = "workshop_plywood"
	other_options["palette_id"] = "plywood_natural"
	var other := BUILDER.prepare_layout(&"workshop", &"wide", FIXTURE_SEED, other_options)
	if not _expect(not prepared.is_empty() and not other.is_empty(), "both material options should still generate"):
		return
	if not _expect(prepared["centerline"] == other["centerline"] and prepared["racing_line_metrics"] == other["racing_line_metrics"], "changing only material options must leave geometry fingerprints unchanged"):
		return
	if not _expect(prepared["spec"]["surface_identity"]["signature"] != other["spec"]["surface_identity"]["signature"] and prepared["spec"]["surface_identity"]["floor"]["id"] != other["spec"]["surface_identity"]["floor"]["id"], "catalog variants should change visible material, not the route"):
		return
	if not _expect(String(prepared["spec"]["material_id"]) == String(identity["material_id"]) and String(prepared["spec"]["palette_id"]) == String(identity["palette_id"]), "prepared layout should publish the same material identity"):
		return
	if not _expect(prepared["spec"]["track_texture"] == prepared["spec"]["surface_identity"]["course"]["texture"] and prepared["spec"]["track_texture"] == prepared["spec"]["floor_texture"], "paint must retain the room's continuous substrate texture"):
		return
	if not _expect(BUILDER.ROOM_COMPOSITIONS == BUILDER.STORY_KITS, "STORY_KITS should remain an alias of room compositions"):
		return

	print("GENERATED_WORLD_MATERIALS_TEST PASS families=12 variants=24")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_WORLD_MATERIALS_TEST FAIL: " + message)
	quit(1)
	return false
