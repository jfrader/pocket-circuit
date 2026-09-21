class_name V8TrackRoomRecipeData
extends RefCounted

static var LEGACY_OUTERS := {
	&"classic": PackedVector2Array([Vector2(-875, -575), Vector2(875, -575), Vector2(875, 575), Vector2(-875, 575)]),
	&"wide": PackedVector2Array([Vector2(-1175, -600), Vector2(1175, -600), Vector2(1175, 600), Vector2(-1175, 600)]),
	&"tall": PackedVector2Array([Vector2(-575, -725), Vector2(575, -725), Vector2(575, 725), Vector2(-575, 725)]),
	&"el": PackedVector2Array([Vector2(-1200, -700), Vector2(360, -700), Vector2(360, -60), Vector2(1200, -60), Vector2(1200, 700), Vector2(-1200, 700)]),
	&"long": PackedVector2Array([Vector2(-1300, -550), Vector2(1300, -550), Vector2(1300, 550), Vector2(-1300, 550)]),
	&"square": PackedVector2Array([Vector2(-750, -750), Vector2(750, -750), Vector2(750, 750), Vector2(-750, 750)]),
}

static var RECIPES := {
	&"classic": {"id": 1, "revision": 1, "half_size": Vector2(1540, 1010), "bevel": 105.0},
	&"wide": {"id": 2, "revision": 1, "half_size": Vector2(2070, 1050), "bevel": 115.0},
	&"tall": {"id": 3, "revision": 1, "half_size": Vector2(1020, 1320), "bevel": 105.0},
	&"el": {"id": 4, "revision": 1, "half_size": Vector2(2100, 1225), "notch": Vector2(630, -105)},
	&"long": {"id": 5, "revision": 1, "half_size": Vector2(2300, 980), "bevel": 100.0},
	&"square": {"id": 6, "revision": 1, "half_size": Vector2(1330, 1330), "bevel": 125.0},
}


static func legacy_outer(family: StringName) -> PackedVector2Array:
	return (LEGACY_OUTERS.get(family, PackedVector2Array()) as PackedVector2Array).duplicate()


static func recipe(family: StringName) -> Dictionary:
	return (RECIPES.get(family, {}) as Dictionary).duplicate(true)


static func families() -> Array[StringName]:
	return [&"classic", &"wide", &"tall", &"el", &"long", &"square"]
