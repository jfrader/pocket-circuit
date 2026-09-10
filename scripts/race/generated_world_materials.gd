class_name GeneratedWorldMaterials
extends RefCounted

const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_TILE := Vector2(1024.0, 1024.0)
const ISLAND_TILE := Vector2(768.0, 768.0)
const STORY_FAMILIES := {
	"breakfast_service": "kitchen_warm_tile",
	"vegetable_prep": "kitchen_sage_tile",
	"afternoon_tea": "kitchen_ceramic",
	"counter_cleanup": "kitchen_stone",
	"carpentry_bench": "workshop_plywood",
	"paint_station": "workshop_honey",
	"repair_job": "workshop_oiled",
	"garage_sort": "workshop_paint",
	"dual_workstation": "office_ash",
	"mail_sort": "office_laminate",
	"sketch_session": "office_walnut",
	"coffee_break": "office_deskmat",
}
const FAMILIES := {
	"kitchen_warm_tile": {
		"theme": "kitchen",
		"label": "Warm tile",
		"floor": "res://assets/textures/world_materials/kitchen_counter.png",
		"island": "res://assets/textures/world_materials/kitchen_board.png",
		"variants": [
			{"id": "warm_tile_sunrise", "tint": Color(1.04, 0.98, 0.9), "track_modulate": 1.08},
			{"id": "warm_tile_hearth", "tint": Color(0.92, 0.84, 0.74), "track_modulate": 1.02},
		],
	},
	"kitchen_sage_tile": {
		"theme": "kitchen",
		"label": "Sage tile",
		"floor": "res://assets/textures/world_materials/kitchen_sage_tile.png",
		"island": "res://assets/textures/world_materials/kitchen_board.png",
		"variants": [
			{"id": "sage_tile_mist", "tint": Color(0.94, 1.0, 0.98), "track_modulate": 1.05},
			{"id": "sage_tile_slate", "tint": Color(0.82, 0.88, 0.94), "track_modulate": 1.0},
		],
	},
	"kitchen_ceramic": {
		"theme": "kitchen",
		"label": "Patterned ceramic",
		"floor": "res://assets/textures/world_materials/kitchen_ceramic.png",
		"island": "res://assets/textures/world_materials/kitchen_board.png",
		"variants": [
			{"id": "ceramic_cream", "tint": Color(1.02, 0.98, 0.92), "track_modulate": 1.06},
			{"id": "ceramic_linen", "tint": Color(0.94, 0.91, 0.86), "track_modulate": 1.01},
		],
	},
	"kitchen_stone": {
		"theme": "kitchen",
		"label": "Light stone",
		"floor": "res://assets/textures/world_materials/kitchen_stone.png",
		"island": "res://assets/textures/world_materials/kitchen_board.png",
		"variants": [
			{"id": "stone_pale", "tint": Color(1.02, 1.0, 0.96), "track_modulate": 1.04},
			{"id": "stone_sand", "tint": Color(0.96, 0.9, 0.8), "track_modulate": 1.0},
		],
	},
	"workshop_plywood": {
		"theme": "workshop",
		"label": "Pale plywood",
		"floor": "res://assets/textures/world_materials/workshop_plywood.png",
		"island": "res://assets/textures/world_materials/workshop_mat.png",
		"variants": [
			{"id": "plywood_natural", "tint": Color(1.02, 0.98, 0.9), "track_modulate": 1.05},
			{"id": "plywood_bleach", "tint": Color(0.96, 0.94, 0.88), "track_modulate": 1.0},
		],
	},
	"workshop_honey": {
		"theme": "workshop",
		"label": "Honey wood",
		"floor": "res://assets/textures/world_materials/workshop_bench.png",
		"island": "res://assets/textures/world_materials/workshop_mat.png",
		"variants": [
			{"id": "honey_amber", "tint": Color(1.06, 0.94, 0.78), "track_modulate": 1.08},
			{"id": "honey_toast", "tint": Color(0.92, 0.8, 0.64), "track_modulate": 1.02},
		],
	},
	"workshop_oiled": {
		"theme": "workshop",
		"label": "Dark oiled bench",
		"floor": "res://assets/textures/world_materials/workshop_oiled.png",
		"island": "res://assets/textures/world_materials/workshop_mat.png",
		"variants": [
			{"id": "oiled_espresso", "tint": Color(0.86, 0.78, 0.7), "track_modulate": 1.0},
			{"id": "oiled_walnut", "tint": Color(0.78, 0.66, 0.54), "track_modulate": 0.96},
		],
	},
	"workshop_paint": {
		"theme": "workshop",
		"label": "Paint-marked wood",
		"floor": "res://assets/textures/world_materials/workshop_paint.png",
		"island": "res://assets/textures/world_materials/workshop_mat.png",
		"variants": [
			{"id": "paint_mark_sage", "tint": Color(0.9, 0.94, 0.88), "track_modulate": 1.04},
			{"id": "paint_mark_rust", "tint": Color(0.96, 0.86, 0.78), "track_modulate": 1.0},
		],
	},
	"office_ash": {
		"theme": "office",
		"label": "Light ash",
		"floor": "res://assets/textures/world_materials/office_desk.png",
		"island": "res://assets/textures/world_materials/office_pad.png",
		"variants": [
			{"id": "ash_daylight", "tint": Color(1.04, 1.02, 0.96), "track_modulate": 1.06},
			{"id": "ash_cool", "tint": Color(0.9, 0.92, 0.94), "track_modulate": 1.0},
		],
	},
	"office_laminate": {
		"theme": "office",
		"label": "Gray laminate",
		"floor": "res://assets/textures/world_materials/office_laminate.png",
		"island": "res://assets/textures/world_materials/office_pad.png",
		"variants": [
			{"id": "laminate_fog", "tint": Color(0.96, 0.96, 0.94), "track_modulate": 1.04},
			{"id": "laminate_graphite", "tint": Color(0.82, 0.84, 0.86), "track_modulate": 0.98},
		],
	},
	"office_walnut": {
		"theme": "office",
		"label": "Warm walnut",
		"floor": "res://assets/textures/world_materials/office_walnut.png",
		"island": "res://assets/textures/world_materials/office_pad.png",
		"variants": [
			{"id": "walnut_honey", "tint": Color(1.04, 0.9, 0.74), "track_modulate": 1.06},
			{"id": "walnut_cocoa", "tint": Color(0.84, 0.7, 0.56), "track_modulate": 1.0},
		],
	},
	"office_deskmat": {
		"theme": "office",
		"label": "Desk mat",
		"floor": "res://assets/textures/world_materials/office_deskmat.png",
		"island": "res://assets/textures/world_materials/office_desk.png",
		"variants": [
			{"id": "deskmat_slate", "tint": Color(0.9, 0.94, 0.96), "track_modulate": 1.02},
			{"id": "deskmat_navy", "tint": Color(0.78, 0.84, 0.92), "track_modulate": 0.98},
		],
	},
}


static func family_id_for_story(theme: StringName, story_id: StringName) -> String:
	var mapped := String(STORY_FAMILIES.get(String(story_id), ""))
	if mapped.is_empty():
		var stories: Array = GENERATED_RULES.STORY_IDS.get(String(theme), [])
		if not stories.is_empty():
			mapped = String(STORY_FAMILIES.get(String(stories[0]), ""))
	return mapped


static func resolve(theme: StringName, story_id: StringName, material_seed: int, explicit_material_id: String = "", explicit_palette_id: String = "") -> Dictionary:
	var family_id := _family_from_explicit(explicit_material_id, explicit_palette_id)
	if family_id.is_empty():
		family_id = family_id_for_story(theme, story_id)
	var family: Dictionary = FAMILIES.get(family_id, {})
	var variant_index := posmod(material_seed, 2)
	var variants: Array = family.get("variants", [])
	if variants.is_empty():
		return _identity_only(explicit_material_id, explicit_palette_id)
	if not explicit_palette_id.is_empty():
		for index in variants.size():
			if String((variants[index] as Dictionary).get("id", "")) == explicit_palette_id:
				variant_index = index
				break
	var variant: Dictionary = variants[variant_index]
	var material_id := explicit_material_id if not explicit_material_id.is_empty() else family_id
	var palette_id := explicit_palette_id if not explicit_palette_id.is_empty() else String(variant["id"])
	var known := _catalog_has_pair(material_id, palette_id)
	var resolved := {
		"material_id": material_id,
		"palette_id": palette_id,
		"family_id": family_id,
		"known": known,
		"label": String(family.get("label", "")),
		"floor_texture": "",
		"track_texture": "",
		"island_material_texture": "",
		"floor_tile_world_size": WORLD_TILE,
		"track_world_tile_size": WORLD_TILE,
		"island_material_world_size": ISLAND_TILE,
		"floor_modulate": Color.WHITE,
		"track_tile_modulate": 1.06,
		"track_opacity": 0.6,
	}
	if not known:
		return resolved
	resolved["floor_texture"] = String(family["floor"])
	resolved["track_texture"] = String(family["floor"])
	resolved["island_material_texture"] = String(family["island"])
	resolved["floor_modulate"] = variant.get("tint", Color.WHITE)
	resolved["track_tile_modulate"] = float(variant.get("track_modulate", 1.06))
	return resolved


static func apply_to_spec(spec: Dictionary, resolved: Dictionary) -> void:
	spec["material_id"] = String(resolved.get("material_id", ""))
	spec["palette_id"] = String(resolved.get("palette_id", ""))
	if not bool(resolved.get("known", false)):
		return
	spec["floor_texture"] = String(resolved["floor_texture"])
	spec["track_texture"] = String(resolved["track_texture"])
	spec["island_material_texture"] = String(resolved["island_material_texture"])
	spec["floor_modulate"] = resolved["floor_modulate"]
	spec["track_tile_modulate"] = resolved["track_tile_modulate"]
	spec["track_opacity"] = resolved["track_opacity"]


static func family_count() -> int:
	return FAMILIES.size()


static func variant_ids(family_id: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var family: Dictionary = FAMILIES.get(family_id, {})
	for variant: Dictionary in family.get("variants", []):
		ids.append(String(variant.get("id", "")))
	return ids


static func _family_from_explicit(material_id: String, palette_id: String) -> String:
	if FAMILIES.has(material_id):
		return material_id
	if palette_id.is_empty():
		return ""
	for family_id: String in FAMILIES.keys():
		for variant: Dictionary in (FAMILIES[family_id] as Dictionary).get("variants", []):
			if String(variant.get("id", "")) == palette_id:
				return String(family_id)
	return ""


static func _catalog_has_pair(material_id: String, palette_id: String) -> bool:
	var family: Dictionary = FAMILIES.get(material_id, {})
	if family.is_empty():
		return false
	for variant: Dictionary in family.get("variants", []):
		if String(variant.get("id", "")) == palette_id:
			return true
	return false


static func _identity_only(material_id: String, palette_id: String) -> Dictionary:
	return {
		"material_id": material_id,
		"palette_id": palette_id,
		"family_id": "",
		"known": false,
		"label": "",
		"floor_texture": "",
		"track_texture": "",
		"island_material_texture": "",
		"floor_tile_world_size": WORLD_TILE,
		"track_world_tile_size": WORLD_TILE,
		"island_material_world_size": ISLAND_TILE,
		"floor_modulate": Color.WHITE,
		"track_tile_modulate": 1.06,
		"track_opacity": 0.6,
	}
