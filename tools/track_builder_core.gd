class_name TrackBuilderCore
## Runtime + headless track builder: builds a painted toy-racing circuit scene
## (spline corridor, island prop, walls, gates, grid, props) from a theme spec,
## a room shape, and a seed. Pure runtime code — no SceneTree/editor deps — so
## the race can generate any arbitrary seed on demand.

const CHECKPOINT_SCENE := "res://scenes/race/checkpoint.tscn"
const HALF_WIDTH := 125.0
const SAMPLE_COUNT := 260
const GATE_COUNT := 8

static var ROOM_SHAPES := {
	"classic": PackedVector2Array([Vector2(-875, -575), Vector2(875, -575), Vector2(875, 575), Vector2(-875, 575)]),
	"wide": PackedVector2Array([Vector2(-1175, -450), Vector2(1175, -450), Vector2(1175, 450), Vector2(-1175, 450)]),
	"tall": PackedVector2Array([Vector2(-575, -725), Vector2(575, -725), Vector2(575, 725), Vector2(-575, 725)]),
	"el": PackedVector2Array([Vector2(-1000, -550), Vector2(300, -550), Vector2(300, -50), Vector2(1000, -50), Vector2(1000, 550), Vector2(-1000, 550)]),
	"long": PackedVector2Array([Vector2(-1300, -400), Vector2(1300, -400), Vector2(1300, 400), Vector2(-1300, 400)]),
	"square": PackedVector2Array([Vector2(-750, -750), Vector2(750, -750), Vector2(750, 750), Vector2(-750, 750)]),
}

static var PROP_SHAPES := {
	"ruler_plank.png": {"shape": "rect", "size": Vector2(96.0, 30.0)},
	"plank_wood.png": {"shape": "rect", "size": Vector2(90.0, 34.0)},
	"book_top.png": {"shape": "rect", "size": Vector2(72.0, 54.0)},
	"remote_control.png": {"shape": "rect", "size": Vector2(64.0, 36.0)},
	"hazard_office_cable.png": {"shape": "rect", "size": Vector2(84.0, 24.0)},
	"hazard_workshop_socket.png": {"shape": "rect", "size": Vector2(84.0, 24.0)},
	"cutting_board.png": {"shape": "rect", "size": Vector2(84.0, 52.0)},
	"frying_pan.png": {"shape": "circle", "size": Vector2.ZERO},
}

const LAYOUTS := {
	&"kitchen": {
		"scene": "res://scenes/tracks/kitchen_graybox.tscn",
		"root_name": "KitchenGraybox",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-640, 370),
			Vector2(-640, 200), Vector2(-640, -200), Vector2(-640, -370), Vector2(-300, -370),
			Vector2(300, -370), Vector2(640, -370), Vector2(640, -200), Vector2(640, 200),
		],
		"floor": Color("3a332c"),
		"highlight": Color("4a4238"),
		"island": Color("4a4038"),
		"asphalt": Color("2e2c28"),
		"apron": Color("3f3830"),
		"track_texture": "res://assets/textures/imagine/track_cloth.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_cloth.png",
		"prop_texture": "res://assets/textures/kitchen/plate_large.png",
		"prop_label": "Plate",
		"edge_texture": "res://assets/textures/kitchen/counter_edge.png",
		"island_expansion": 10.0,
		"scatter_textures": [
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		],
		"island_fill_textures": [
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
			"res://assets/textures/kitchen/mug_blue.png",
			"res://assets/textures/kitchen/cereal_tower_green.png",
			"res://assets/textures/imagine/frying_pan.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/teacup_saucer.png",
			"res://assets/textures/imagine/salt_shaker.png",
			"res://assets/textures/imagine/mug_top.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/kitchen/cutting_board.png",
			"res://assets/textures/imagine/watermelon.png",
			"res://assets/textures/imagine/frying_pan.png",
			"res://assets/textures/imagine/teapot_top.png",
			"res://assets/textures/imagine/vase_top.png",
			"res://assets/textures/imagine/plate_stack.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/plant_small.png",
		],
		"decals": [
			"res://assets/textures/imagine/crumb_cluster.png",
			"res://assets/textures/imagine/stain_ring.png",
		],
		"obstacles": {
			"MugA": {"pos": Vector2(-300, 290), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_hero.png"},
			"MugB": {"pos": Vector2(-60, 500), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_blue.png"},
			"Apple": {"pos": Vector2(-500, 35), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-390, 120), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-510, 520), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
		},
	},
	&"workshop": {
		"scene": "res://scenes/tracks/workshop_workbench.tscn",
		"root_name": "WorkshopWorkbench",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-735, 330),
			Vector2(-735, 0), Vector2(-735, -250), Vector2(-600, -420), Vector2(-300, -470),
			Vector2(0, -480), Vector2(300, -470), Vector2(600, -420), Vector2(735, -250),
			Vector2(735, 0), Vector2(735, 370),
		],
		"floor": Color("7a5a3f"),
		"highlight": Color("8a6a4f"),
		"island": Color("4a4038"),
		"asphalt": Color("2e2c28"),
		"apron": Color("5c4638"),
		"track_texture": "res://assets/textures/imagine/track_wood.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_wood.png",
		"prop_texture": "res://assets/textures/imagine/workshop_toolbox_top_bright.jpg",
		"prop_label": "Toolbox",
		"edge_texture": "res://assets/textures/imagine/workshop_edge_bright.png",
		"scatter_textures": [
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/kitchen/ruler_plank.png",
		],
		"island_fill_textures": [
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/workshop_paint_can.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/fork_cartoon.png",
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/wrench.png",
			"res://assets/textures/imagine/hammer.png",
			"res://assets/textures/imagine/remote_control.png",
			"res://assets/textures/imagine/screwdriver.png",
			"res://assets/textures/imagine/tape_roll.png",
			"res://assets/textures/imagine/matchbox.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/workshop_toolbox_top_bright.jpg",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/basketball.png",
			"res://assets/textures/imagine/soccer_ball.png",
			"res://assets/textures/imagine/football.png",
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/bottle_top.png",
			"res://assets/textures/imagine/teapot_top.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/kitchen/spoon_bridge.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/kitchen/cup_cartoon.png",
		],
		"decals": [
			"res://assets/textures/imagine/sawdust_patch.png",
			"res://assets/textures/imagine/oil_stain.png",
		],
		"island_expansion": 10.0,
		"obstacles": {
			"CerealA": {"pos": Vector2(300, 430), "r": 38.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"MugA": {"pos": Vector2(-300, 290), "r": 36.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"MugB": {"pos": Vector2(-60, 500), "r": 36.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
			"Sponge": {"pos": Vector2(-180, 300), "r": 34.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			"Ruler": {"pos": Vector2(-60, 290), "r": 32.0, "tex": "res://assets/textures/kitchen/ruler_plank.png"},
			"Fork": {"pos": Vector2(-820, -330), "r": 34.0, "tex": "res://assets/textures/kitchen/fork_cartoon.png"},
			"Spoon": {"pos": Vector2(830, -80), "r": 36.0, "tex": "res://assets/textures/imagine/hazard_workshop_socket.png"},
			"Apple": {"pos": Vector2(-500, 35), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-390, 120), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-510, 520), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
			"CerealB": {"pos": Vector2(200, -60), "r": 36.0, "tex": "res://assets/textures/kitchen/cereal_tower_green.png"},
		},
		"apron_props": [
															{"pos": Vector2(-560, -260), "r": 26.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			{"pos": Vector2(-450, -300), "r": 24.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			{"pos": Vector2(-510, -180), "r": 22.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			{"pos": Vector2(120, -520), "r": 30.0, "tex": "res://assets/textures/imagine/hazard_workshop_socket.png"},
			{"pos": Vector2(260, -560), "r": 26.0, "tex": "res://assets/textures/imagine/workshop_paint_can.png"},
		],
	},
	&"office": {
		"scene": "res://scenes/tracks/office_desk.tscn",
		"root_name": "OfficeDesk",
		"controls": [
			Vector2(640, 370), Vector2(300, 370), Vector2(-300, 370), Vector2(-400, 340),
			Vector2(-700, 260), Vector2(-820, 215), Vector2(-750, 180), Vector2(-600, 112),
			Vector2(-400, 22), Vector2(-200, -67), Vector2(0, -157), Vector2(200, -246),
			Vector2(400, -336), Vector2(600, -420), Vector2(735, -300), Vector2(735, 0),
			Vector2(735, 370),
		],
		"floor": Color("4a6a8a"),
		"highlight": Color("5a7a9a"),
		"island": Color("3a5a7a"),
		"asphalt": Color("272b31"),
		"apron": Color("3a4a5a"),
		"track_texture": "res://assets/textures/imagine/track_pad.png",
		"track_tile_modulate": 1.0,
		"floor_texture": "res://assets/textures/imagine/floor_pad.png",
		"prop_texture": "res://assets/textures/imagine/office_keyboard_top_bright.jpg",
		"prop_label": "Keyboard",
		"edge_texture": "res://assets/textures/imagine/office_edge_bright.png",
		"scatter_textures": [
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/imagine/hazard_office_cable.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
		],
		"island_fill_textures": [
			"res://assets/textures/imagine/book_top.png",
			"res://assets/textures/imagine/plank_wood.png",
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/remote_control.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/stapler_top.png",
			"res://assets/textures/imagine/pencil.png",
			"res://assets/textures/imagine/crayons.png",
			"res://assets/textures/imagine/scissors_top.png",
			"res://assets/textures/imagine/tape_roll.png",
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/office_keyboard_top_bright.jpg",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/lamp_desk.png",
			"res://assets/textures/imagine/mug_top.png",
			"res://assets/textures/imagine/plate_stack.png",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
			"res://assets/textures/imagine/strawberry.png",
			"res://assets/textures/imagine/bolt.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
			"res://assets/textures/imagine/plant_small.png",
			"res://assets/textures/imagine/keys_ring.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
			"res://assets/textures/imagine/screw.png",
			"res://assets/textures/imagine/coin.png",
		],
		"boundary_long": [
			"res://assets/textures/kitchen/ruler_plank.png",
			"res://assets/textures/imagine/office_keycap.png",
			"res://assets/textures/imagine/hazard_office_cable.png",
		],
		"boundary_corner": [
			"res://assets/textures/imagine/flower_pot.png",
			"res://assets/textures/imagine/barrel_wood.png",
			"res://assets/textures/imagine/plant_small.png",
		],
		"decals": [
			"res://assets/textures/imagine/paper_sheet.png",
			"res://assets/textures/imagine/stain_ring.png",
		],
		"island_expansion": 4.0,
		"gate_fractions": [0.0, 0.125, 0.25, 0.43, 0.55, 0.67, 0.72, 0.74],
		"obstacles": {
			"CerealA": {"pos": Vector2(300, 430), "r": 38.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			"MugA": {"pos": Vector2(-300, 500), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_hero.png"},
			"MugB": {"pos": Vector2(-60, 520), "r": 36.0, "tex": "res://assets/textures/imagine/kitchen_mug_blue.png"},
			"Sponge": {"pos": Vector2(-180, 300), "r": 34.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			"Ruler": {"pos": Vector2(-60, 200), "r": 32.0, "tex": "res://assets/textures/kitchen/ruler_plank.png"},
			"Fork": {"pos": Vector2(-820, -330), "r": 34.0, "tex": "res://assets/textures/kitchen/fork_cartoon.png"},
			"Spoon": {"pos": Vector2(830, 120), "r": 36.0, "tex": "res://assets/textures/imagine/hazard_office_cable.png"},
			"Apple": {"pos": Vector2(-470, 60), "r": 36.0, "tex": "res://assets/textures/kitchen/apple_cartoon.png"},
			"Lime": {"pos": Vector2(-410, 170), "r": 36.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			"Cup": {"pos": Vector2(-560, 540), "r": 36.0, "tex": "res://assets/textures/kitchen/cup_cartoon.png"},
			"CerealB": {"pos": Vector2(200, -60), "r": 36.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
		},
		"apron_props": [
			{"pos": Vector2(-300, -340), "r": 24.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			{"pos": Vector2(-500, -420), "r": 22.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
			{"pos": Vector2(-180, -480), "r": 26.0, "tex": "res://assets/textures/kitchen/sponge_wet.png"},
			{"pos": Vector2(-420, -560), "r": 24.0, "tex": "res://assets/textures/kitchen/lime_cartoon.png"},
			{"pos": Vector2(180, -560), "r": 22.0, "tex": "res://assets/textures/imagine/office_keycap.png"},
		],
	},
}


static func build_packed(theme: StringName, room_shape: StringName, seed: int) -> Dictionary:
	var spec: Dictionary = LAYOUTS[theme]
	var room_polygon: PackedVector2Array = ROOM_SHAPES[room_shape]
	var used_seed := seed
	if seed >= 0:
		var room_params := {
			"margin": 150.0,
			"min_point_distance": 210.0,
			"max_angle_deg": 80.0,
			"min_self_distance": 280.0,
			"min_loop_length": 1900.0,
			"room_polygon": room_polygon,
		}
		match room_shape:
			&"tall":
				room_params["min_self_distance"] = 252.0
				room_params["displacement_scale"] = 0.55
			&"el":
				room_params["min_self_distance"] = 220.0
				room_params["displacement_scale"] = 0.5
				room_params["min_loop_length"] = 1500.0
				room_params["sample_rect"] = Rect2(-1000, -550, 1300, 1100)
				room_params["room_check_margin"] = 2.0
			&"long":
				room_params["min_self_distance"] = 280.0
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2000.0
			&"square":
				room_params["min_self_distance"] = 280.0
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2200.0
		var gen := TrackSeedGen.generate_with_retries(seed, Rect2(-940, -540, 1880, 1080), room_params)
		if gen["points"].is_empty():
			push_error("TrackBuilderCore: could not generate a valid circuit near seed " + str(seed))
			return {"scene": null, "seed": seed}
		spec = spec.duplicate()
		spec["controls"] = gen["points"]
		spec["seed_obstacles"] = true
		spec["seed"] = int(gen["seed"])
		spec["island_expansion"] = 10.0
		spec.erase("gate_fractions")
		used_seed = int(gen["seed"])
	var root := Node2D.new()
	root.name = String(spec["root_name"])
	root.add_to_group("track")
	var centerline := _sample_centerline(spec["controls"])
	var edges := _corridor_edges(centerline)
	_build_scene(root, spec, centerline, edges, room_polygon, theme)
	_mark_owned(root)
	var packed := PackedScene.new()
	packed.pack(root)
	return {"scene": packed, "seed": used_seed}


static func _sample_centerline(controls: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SAMPLE_COUNT:
		points.append(_catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


static func _catmull_rom_closed(points: Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var i := int(floor(scaled))
	var local := scaled - float(i)
	var p0: Vector2 = points[posmod(i - 1, count)]
	var p1: Vector2 = points[posmod(i, count)]
	var p2: Vector2 = points[posmod(i + 1, count)]
	var p3: Vector2 = points[posmod(i + 2, count)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * local
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * local * local
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * local * local * local
	)


static func _corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		left.append(centerline[index] + normal * HALF_WIDTH)
		right.append(centerline[index] - normal * HALF_WIDTH)
	return {"left": left, "right": right, "centerline": centerline}


static func _build_scene(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary, room_polygon: PackedVector2Array, theme: StringName) -> void:
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]

	# Floor: base fill extends well past the room so the camera never sees a void,
	# themed texture tiles on top at full brightness
	var floor_texture := String(spec.get("floor_texture", ""))
	_add_polygon(root, "Floor", _rect_points(Vector2(-600, -500), Vector2(2600, 1700)), spec["floor"], -22)
	_add_polygon(root, "CounterHighlight", _rect_points(Vector2(-940, -540), Vector2(940, 540)), Color(spec["highlight"], 0.5), -21)
	if not floor_texture.is_empty():
		_add_floor_tiles(root, floor_texture, Vector2(-600, -500), Vector2(2600, 1700), 6, 4, Vector2(1.0, 1.0))
	var room_surface := _expand_loop(room_polygon, 26.0)
	_add_textured_polygon(root, "RoomSurface", room_surface, floor_texture, spec["highlight"], -20)

	# Painted track ribbon (visual only — no collision)
	var corridor := PackedVector2Array()
	corridor.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		corridor.append(right[index])
	var clipped_pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(room_polygon, corridor)
	var clipped := PackedVector2Array()
	for piece: PackedVector2Array in clipped_pieces:
		if piece.size() > clipped.size():
			clipped = piece
	_add_polygon(root, "TrackRibbon", clipped, Color(1.0, 0.96, 0.88, 0.17), -10)
	var track_texture := String(spec.get("track_texture", ""))
	if not track_texture.is_empty():
		_add_centerline_tiles(root, centerline, track_texture, Vector2(0.30, 0.30), float(spec.get("track_tile_modulate", 1.35)))

	# No painted delimitation lines: the ribbon, island prop, and placed props
	# define the course
	var outer_loop := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	var inner_loop := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
	var island_region := _island_region(room_polygon, clipped, inner_loop)
	_build_island_prop(root, spec, island_region, inner_loop, centerline)

	# Room walls (real furniture edges along the room outline)
	var edge_texture := String(spec.get("edge_texture", "res://assets/textures/kitchen/counter_edge.png"))
	var wall_index := 0
	for index in room_polygon.size():
		var from: Vector2 = room_polygon[index]
		var to: Vector2 = room_polygon[(index + 1) % room_polygon.size()]
		var mid := (from + to) * 0.5
		var edge_vector := to - from
		var length := edge_vector.length()
		if length < 1.0:
			continue
		_add_wall_segment(root, "Wall%d" % wall_index, mid, length, atan2(edge_vector.y, edge_vector.x), edge_texture)
		wall_index += 1

	# Checkpoints along the arc, aligned to the tangent. The last lap gate sits
	# slightly past the corner rejoin so its recovery point stays on a straight.
	var gate_fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := _arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	var start := centerline[0]
	var start_tangent := (centerline[1] - centerline[centerline.size() - 1]).normalized()
	var gate_samples := PackedVector2Array()
	for gate_index in GATE_COUNT:
		var fraction: float = gate_fractions[gate_index]
		var sample := _sample_at_arc(centerline, arc, total * fraction)
		gate_samples.append(sample)
		var tangent := _tangent_at_arc(centerline, arc, total * fraction)
		var rotation := atan2(-tangent.y, -tangent.x)
		var is_finish := gate_index == 0
		var name := "Checkpoint0Finish" if is_finish else "Checkpoint%d" % gate_index
		_add_cp(root, name, sample, rotation, gate_index, is_finish, atan2(tangent.x, -tangent.y))

	# Bold checker strip at the finish gate (two alternating rows across the corridor)
	var finish_normal := start_tangent.rotated(PI * 0.5)
	var strip_half := Vector2(finish_normal.y, -finish_normal.x) * HALF_WIDTH
	var checker_white := PackedVector2Array()
	var checker_black := PackedVector2Array()
	var checker_count := 6
	var cell_half := Vector2(finish_normal.y, -finish_normal.x) * (HALF_WIDTH / float(checker_count))
	for row in 2:
		var row_center := start + finish_normal * (30.0 - float(row) * 60.0)
		for column in checker_count:
			var cell_center := row_center + cell_half * (float(column) * 2.0 - float(checker_count - 1))
			var cell_color := Color("f5eec8") if (column + row) % 2 == 0 else Color("0d0f14")
			var target: PackedVector2Array = checker_white if (column + row) % 2 == 0 else checker_black
			target.append(cell_center + finish_normal * 30.0 + cell_half)
			target.append(cell_center + finish_normal * 30.0 - cell_half)
			target.append(cell_center - finish_normal * 30.0 - cell_half)
			target.append(cell_center - finish_normal * 30.0 + cell_half)
	_add_polygon(root, "StartFinishWhite", checker_white, Color("f5eec8"), -7)
	_add_polygon(root, "StartFinishBlack", checker_black, Color("0d0f14"), -6)

	# Aligned 2x2 grids past the finish line, on the driving side
	var grid_normal := finish_normal
	_add_grid(root, "GridForward", atan2(start_tangent.x, -start_tangent.y), [
		start + start_tangent * 100.0 - grid_normal * 45.0,
		start + start_tangent * 100.0 + grid_normal * 45.0,
		start + start_tangent * 220.0 - grid_normal * 45.0,
		start + start_tangent * 220.0 + grid_normal * 45.0,
	])
	var reverse_rotation := atan2(-start_tangent.x, start_tangent.y)
	_add_grid(root, "GridReverse", reverse_rotation, [
		start - start_tangent * 45.0 - grid_normal * 45.0,
		start - start_tangent * 45.0 + grid_normal * 45.0,
		start - start_tangent * 120.0 - grid_normal * 45.0,
		start - start_tangent * 120.0 + grid_normal * 45.0,
	])

	# Dense collidable fill over the whole island interior (books, planks, hose…)
	_fill_island(root, spec, inner_loop, centerline)

	# Props delimiting the outer side of the track (long on straights, bulky on corners)
	if not OS.get_environment("PC_NO_BOUNDARY") == "1":
		_line_boundary_props(root, spec, centerline, outer_loop, clipped, room_polygon)
	var decal_rng := RandomNumberGenerator.new()
	decal_rng.seed = int(spec.get("seed", 0)) * 31 + 7
	_scatter_decals(root, spec, room_polygon, corridor, decal_rng)

	# Track obstacles (real props with collision)
	if spec.get("seed_obstacles", false):
		_scatter_seed_props(root, spec, centerline, clipped, gate_samples, room_polygon)
	else:
		var obstacles: Dictionary = spec["obstacles"]
		for obstacle_name: String in obstacles:
			var data: Dictionary = obstacles[obstacle_name]
			_add_obstacle(root, obstacle_name, data["pos"], float(data["r"]), String(data["tex"]))

		# Apron furniture: real objects off the racing line, some with collision
		var apron_props: Array = spec.get("apron_props", [])
		for prop: Dictionary in apron_props:
			_add_prop_with_collision(root, prop["pos"], float(prop["r"]), String(prop["tex"]))

	# Loose hardware line along the outer edge of the track wherever it turns
	# away from the room walls (channels the racing line without invisible walls)
	var outer_loop2 := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	var prop_textures := [
		"res://assets/textures/kitchen/lime_cartoon.png",
		"res://assets/textures/kitchen/apple_cartoon.png",
		"res://assets/textures/imagine/hazard_workshop_socket.png",
		"res://assets/textures/kitchen/sponge_wet.png",
	]
	var hardware_index := 0
	for index in range(24, centerline.size() - 24, 6):
		var tangent := (centerline[(index + 1) % centerline.size()] - centerline[(index - 1 + centerline.size()) % centerline.size()]).normalized()
		if absf(tangent.x) < 0.45 or absf(tangent.y) < 0.45:
			continue
		var outward := (outer_loop2[index] - centerline[index]).normalized()
		var prop_position := centerline[index] + outward * 175.0
		if not Geometry2D.is_point_in_polygon(prop_position, room_polygon):
			continue
		if not Geometry2D.is_point_in_polygon(prop_position, corridor):
			_add_prop_with_collision(root, prop_position, 30.0, prop_textures[hardware_index % prop_textures.size()])
			hardware_index += 1


	# Start banner above the finish line
	_add_start_banner(root, start, start_tangent, corridor)


static func _build_island_prop(root: Node2D, spec: Dictionary, region: PackedVector2Array, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	var expanded := PackedVector2Array()
	var last := Vector2(INF, INF)
	for index in inner_loop.size():
		var toward_track := (centerline[index] - inner_loop[index]).normalized()
		var point := inner_loop[index] + toward_track * float(spec.get("island_expansion", 10.0))
		if point.distance_to(last) > 3.0:
			expanded.append(point)
			last = point
	var barrier := StaticBody2D.new()
	barrier.name = "InnerBarrier"
	barrier.collision_layer = 2
	root.add_child(barrier)
	var barrier_collision := CollisionPolygon2D.new()
	barrier_collision.polygon = expanded
	barrier.add_child(barrier_collision)

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in region:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))

	var visual := Polygon2D.new()
	visual.name = "IslandProp"
	visual.z_index = -9
	visual.polygon = region
	var prop_texture := String(spec.get("prop_texture", ""))
	var texture := load(prop_texture) as Texture2D if not prop_texture.is_empty() else null
	if texture:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.modulate = Color(1.2, 1.2, 1.2)
		var uvs := PackedVector2Array()
		for point: Vector2 in region:
			uvs.append(Vector2(
				(point.x - min_point.x) / maxf(max_point.x - min_point.x, 1.0),
				(point.y - min_point.y) / maxf(max_point.y - min_point.y, 1.0)
			))
		visual.uv = uvs
	else:
		visual.color = spec["island"]
	root.add_child(visual)


static func _island_region(room_polygon: PackedVector2Array, ribbon: PackedVector2Array, hint_polygon: PackedVector2Array) -> PackedVector2Array:
	var pieces: Array[PackedVector2Array] = Geometry2D.clip_polygons(room_polygon, ribbon)
	var hint_centroid := Vector2.ZERO
	for point: Vector2 in hint_polygon:
		hint_centroid += point
	hint_centroid /= float(hint_polygon.size())
	var best := PackedVector2Array()
	var best_score := -1.0
	for piece: PackedVector2Array in pieces:
		var score := 0.0
		for sample in 40:
			var index := int(float(sample) * float(hint_polygon.size()) / 40.0)
			var hint_point: Vector2 = hint_polygon[index].lerp(hint_centroid, 0.3)
			if Geometry2D.is_point_in_polygon(hint_point, piece):
				score += 1.0
		if score > best_score:
			best_score = score
			best = piece
	return best


static func _rounded_rect_points(center: Vector2, size: Vector2, radius: float, corner_segments: int) -> PackedVector2Array:
	var half := size * 0.5 - Vector2(radius, radius)
	var points := PackedVector2Array()
	for corner: Dictionary in [
		{"c": center + Vector2(half.x, half.y), "start": 0.0},
		{"c": center + Vector2(-half.x, half.y), "start": PI * 0.5},
		{"c": center - half, "start": PI},
		{"c": center + Vector2(half.x, -half.y), "start": PI * 1.5},
	]:
		for seg in corner_segments + 1:
			var angle: float = corner["start"] + PI * 0.5 * float(seg) / float(corner_segments)
			points.append(corner["c"] + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


static func _arc_lengths(centerline: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array()
	arc.append(0.0)
	var running := 0.0
	for index in range(1, centerline.size()):
		running += centerline[index].distance_to(centerline[index - 1])
		arc.append(running)
	return arc


static func _sample_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			var fraction := (target - arc[index - 1]) / maxf(arc[index] - arc[index - 1], 0.001)
			return centerline[index - 1].lerp(centerline[index], fraction)
	return centerline[centerline.size() - 1]


static func _tangent_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			return (centerline[index] - centerline[index - 1]).normalized()
	return (centerline[0] - centerline[centerline.size() - 1]).normalized()


static func _rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])


static func _add_polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color, z: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = z
	parent.add_child(polygon)


static func _add_wall_segment(parent: Node, node_name: String, position: Vector2, length: float, rotation: float, edge_texture_path: String) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.position = position
	wall.rotation = rotation
	wall.collision_layer = 2
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length + 60.0, 50.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.add_child(cs)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = _rect_points(Vector2.ZERO, Vector2(length + 60.0, 50.0))
	visual.color = Color("0e1524")
	wall.add_child(visual)
	var edge_texture := load(edge_texture_path) as Texture2D
	if edge_texture:
		var tile_count := maxi(1, int(ceil((length + 60.0) / 1024.0)))
		for tile in tile_count:
			var strip := Sprite2D.new()
			strip.name = "EdgeStrip"
			strip.texture = edge_texture
			strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var offset := (float(tile) - float(tile_count - 1) * 0.5) * ((length + 60.0) / float(tile_count))
			strip.position = Vector2(offset, 0.0)
			strip.scale = Vector2((length + 60.0) / (1024.0 * float(tile_count)), 50.0 / 220.0)
			wall.add_child(strip)


static func _add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float) -> void:
	var cp := (load(CHECKPOINT_SCENE) as PackedScene).instantiate()
	cp.name = node_name
	cp.position = position
	cp.rotation = rotation
	cp.set("checkpoint_index", index)
	cp.set("is_finish_line", is_finish)
	cp.set("recovery_rotation", recovery_rotation)
	cp.set("recovery_offset", 70.0)
	if not is_finish:
		var collision := cp.get_node("CollisionShape2D") as CollisionShape2D
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(70.0, 300.0)
		collision.shape = forgiving
	parent.add_child(cp)


static func _add_grid(parent: Node, node_name: String, rotation: float, positions: Array) -> void:
	var grid := Node2D.new()
	grid.name = node_name
	parent.add_child(grid)
	for index in positions.size():
		var marker := Node2D.new()
		marker.name = str(index)
		marker.position = positions[index]
		marker.rotation = rotation
		grid.add_child(marker)


static func _scatter_decals(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return
	for decal in 18:
		var position := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(position, corridor):
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Decal"
		sprite.texture = load(String(decals[rng.randi_range(0, decals.size() - 1)])) as Texture2D
		if sprite.texture == null:
			sprite.free()
			continue
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 1.1)
		sprite.rotation = rng.randf_range(0.0, TAU)
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.5, 0.85))
		sprite.z_index = -15
		root.add_child(sprite)


static func _scatter_seed_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, corridor: PackedVector2Array, gate_samples: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var textures: Array = spec.get("scatter_textures", [])
	if textures.is_empty():
		return
	var count := centerline.size()

	var clear_of_gates := _seed_clear_of_gates.bind(gate_samples)

	# a) corridor slalom: a few props on straights, offset from the racing line
	var corridor_props := PackedVector2Array()
	for attempt in 200:
		var index := rng.randi_range(0, count - 1)
		var sample := centerline[index]
		if sample.distance_to(centerline[0]) < 380.0:
			continue
		if not clear_of_gates.call(sample):
			continue
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		var candidate := sample + normal * (95.0 if rng.randf() < 0.5 else -95.0)
		var too_close := false
		for placed: Vector2 in corridor_props:
			if placed.distance_to(candidate) < 240.0:
				too_close = true
				break
		if too_close or not Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		corridor_props.append(candidate)
		if corridor_props.size() >= 3:
			break
	for position: Vector2 in corridor_props:
		_add_scatter_prop(root, position, 34.0, String(textures[rng.randi_range(0, textures.size() - 1)]))

	# b) apron clutter outside the loop
	var apron_props := PackedVector2Array()
	for attempt in 400:
		var candidate := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		if _point_in_loop(candidate, centerline):
			continue
		if not clear_of_gates.call(candidate):
			continue
		var too_close := false
		for placed: Vector2 in apron_props:
			if placed.distance_to(candidate) < 90.0:
				too_close = true
				break
		if too_close:
			continue
		apron_props.append(candidate)
		if apron_props.size() >= 10:
			break
	for position: Vector2 in apron_props:
		_add_prop_with_collision(root, position, 30.0, String(textures[rng.randi_range(0, textures.size() - 1)]))


static func _fill_island(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	var textures: Array = spec.get("island_fill_textures", [])
	if textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in inner_loop:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	var pitch := 84.0
	# Bucket valid cells by how much prop clearance the corridor leaves there:
	# deep-center cells may host big items, edge cells only small ones.
	var buckets := {15.0: PackedVector2Array(), 25.0: PackedVector2Array(), 36.0: PackedVector2Array(), 50.0: PackedVector2Array()}
	for row in range(int(ceil((max_point.y - min_point.y) / pitch)) + 1):
		for column in range(int(ceil((max_point.x - min_point.x) / pitch)) + 1):
			var center := Vector2(
				min_point.x + float(column) * pitch + rng.randf_range(-12.0, 12.0),
				min_point.y + float(row) * pitch + rng.randf_range(-12.0, 12.0))
			if not Geometry2D.is_point_in_polygon(center, inner_loop):
				continue
			var center_distance := _distance_to_centerline(center, centerline)
			if center_distance < 125.0 + 40.0:
				continue
			for tier: float in [50.0, 36.0, 25.0, 15.0]:
				if center_distance >= 125.0 + tier + 40.0:
					buckets[tier].append(center)
					break
	var placed := {}
	var used := {}
	# Pass 1: one of each big and medium item, nearest the island center
	var centroid := (min_point + max_point) * 0.5
	for tier: float in [50.0, 36.0]:
		var pool: Array = spec.get("island_fill_big", []) if tier == 50.0 else spec.get("island_fill_textures", [])
		var cells: Array[Vector2] = []
		cells.append_array(buckets[tier])
		cells.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(centroid) < b.distance_to(centroid))
		for texture in pool:
			if cells.is_empty():
				break
			var texture_path := String(texture)
			if used.get(texture_path, 0) >= 1:
				continue
			var cell: Vector2 = cells.pop_front()
			_add_fill_prop(root, cell, tier, texture_path, rng.randf_range(0.0, TAU))
			used[texture_path] = used.get(texture_path, 0) + 1
			placed[cell] = true
	# Pass 2: remaining cells get small/tiny props, each texture capped at 3
	var small_pool: Array = spec.get("island_fill_small", [])
	var tiny_pool: Array = spec.get("island_fill_tiny", [])
	for tier: float in [25.0, 15.0]:
		var pool := small_pool if tier == 25.0 else tiny_pool
		for cell: Vector2 in buckets[tier]:
			if placed.has(cell):
				continue
			var texture_path := String(pool[rng.randi_range(0, pool.size() - 1)]) if not pool.is_empty() else String(textures[0])
			if used.get(texture_path, 0) >= 3:
				continue
			_add_fill_prop(root, cell, tier, texture_path, rng.randf_range(0.0, TAU))
			used[texture_path] = used.get(texture_path, 0) + 1


static func _cell_clear_of_corridor(center: Vector2, radius: float, corridor: PackedVector2Array) -> bool:
	for sample in 8:
		var angle := TAU * float(sample) / 8.0
		if Geometry2D.is_point_in_polygon(center + Vector2(cos(angle), sin(angle)) * (radius + 40.0), corridor):
			return false
	return true


static func _line_boundary_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, corridor: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Props delimiting the OUTER side of the track: long flat props on straights,
	# bulky props on corners, placed just outside the painted corridor. The
	# corridor-band test is distance-to-centerline (polygon membership is
	# unreliable inside the corridor's fold regions).
	var long_pool: Array = spec.get("boundary_long", [])
	var corner_pool: Array = spec.get("boundary_corner", [])
	if long_pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var count := centerline.size()
	var index := 0
	while index < count - 1:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var ahead := centerline[(index + 8) % count] - centerline[(index - 8 + count) % count]
		var turn := tangent.angle_to(ahead.normalized())
		var is_corner := absf(turn) > 0.16
		var offset := 78.0 if is_corner else 65.0
		var radius := 34.0 if is_corner else 27.0
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * offset
		if position.distance_to(centerline[0]) < 230.0:
			index += 7
			continue
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			index += 7
			continue
		if _distance_to_centerline(position, centerline) < 150.0:
			index += 7
			continue
		var pool := corner_pool if is_corner else long_pool
		var texture_path := String(pool[rng.randi_range(0, pool.size() - 1)])
		var prop_rotation := rng.randf_range(0.0, TAU) if is_corner else tangent.angle()
		_add_boundary_prop(root, position, radius, texture_path, prop_rotation)
		index += 7


static func _distance_to_centerline(point: Vector2, centerline: PackedVector2Array) -> float:
	var best := 999999.0
	for sample: Vector2 in centerline:
		best = minf(best, point.distance_to(sample))
	return best


static func _add_shape_collision(parent: Node, texture_path: String, scale_radius: float) -> void:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	if entry.get("shape", "circle") == "rect":
		var rect := RectangleShape2D.new()
		rect.size = entry["size"]
		var rect_cs := CollisionShape2D.new()
		rect_cs.shape = rect
		parent.add_child(rect_cs)
		return
	var circle := CircleShape2D.new()
	circle.radius = scale_radius
	var circle_cs := CollisionShape2D.new()
	circle_cs.shape = circle
	parent.add_child(circle_cs)


static func _add_boundary_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "BoundaryProp"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_shape_collision(prop, texture_path, radius)
	_add_contact_shadow(prop, radius * 1.15)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "IslandFill"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_contact_shadow(prop, radius * 1.15)
	_add_shape_collision(prop, texture_path, radius)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _add_contact_shadow(parent: Node, radius: float) -> void:
	var shadow := Sprite2D.new()
	shadow.name = "ContactShadow"
	shadow.texture = _contact_shadow_texture()
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.scale = Vector2.ONE * (radius * 2.4 / 128.0)
	shadow.modulate = Color(0.06, 0.05, 0.05, 0.35)
	shadow.z_index = -1
	parent.add_child(shadow)


static var _cached_contact_shadow: Texture2D = null


static func _contact_shadow_texture() -> Texture2D:
	if _cached_contact_shadow != null:
		return _cached_contact_shadow
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var dx := (float(x) - 63.5) / 58.0
			var dy := (float(y) - 63.5) / 58.0
			var falloff := clampf(1.0 - (dx * dx + dy * dy), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff * falloff))
	_cached_contact_shadow = ImageTexture.create_from_image(image)
	return _cached_contact_shadow


static func _add_scatter_prop(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "SeedCorridor"
	prop.position = position
	prop.collision_layer = 16
	parent.add_child(prop)
	_add_shape_collision(prop, texture_path, radius)
	_add_contact_shadow(prop, radius * 1.15)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _seed_clear_of_gates(point: Vector2, gate_samples: PackedVector2Array) -> bool:
	for gate: Vector2 in gate_samples:
		if point.distance_to(gate) < 160.0:
			return false
	return true


static func _point_in_loop(point: Vector2, loop: PackedVector2Array) -> bool:
	var inside := false
	var count := loop.size()
	for index in count:
		var a := loop[index]
		var b := loop[(index + 1) % count]
		if ((a.y > point.y) != (b.y > point.y)) and (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
	return inside


static func _add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = node_name
	obstacle.position = position
	obstacle.collision_layer = 2
	parent.add_child(obstacle)
	_add_shape_collision(obstacle, texture_path, radius)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.4 / maxf(longest, 1.0))
		obstacle.add_child(sprite)


static func _add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "ApronProp"
	prop.position = position
	prop.collision_layer = 2
	parent.add_child(prop)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	prop.add_child(cs)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.4 / maxf(longest, 1.0))
		prop.add_child(sprite)


static func _add_prop(parent: Node, texture_path: String, position: Vector2, scale: float, rotation: float, z: int) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = position
	sprite.rotation = rotation
	sprite.scale = Vector2.ONE * scale
	sprite.z_index = z
	parent.add_child(sprite)


static func _add_sticky_notes(parent: Node, center: Vector2, rotation: float) -> void:
	for offset: Vector2 in [Vector2(-30, -14), Vector2(0, 8), Vector2(26, -6)]:
		var note := Polygon2D.new()
		note.polygon = PackedVector2Array([
			Vector2(-34, -30), Vector2(34, -30), Vector2(34, 30), Vector2(-34, 30),
		])
		note.color = Color("f4bf3a") if offset.x < 0.0 else Color("f2ead7")
		note.position = center + offset
		note.rotation = rotation + (0.1 if offset.x == 0.0 else 0.0)
		note.z_index = -12
		parent.add_child(note)


static func _add_cable_line(parent: Node, points: Array) -> void:
	var line := Line2D.new()
	var packed := PackedVector2Array()
	for point: Vector2 in points:
		packed.append(point)
	line.points = packed
	line.width = 9.0
	line.default_color = Color("6f91b8")
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -12
	parent.add_child(line)


static func _add_textured_polygon(parent: Node, node_name: String, points: PackedVector2Array, texture_path: String, fallback_color: Color, z: int) -> void:
	var visual := Polygon2D.new()
	visual.name = node_name
	visual.z_index = z
	visual.polygon = points
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	if texture:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var min_point := Vector2(INF, INF)
		for point: Vector2 in points:
			min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		var uvs := PackedVector2Array()
		for point: Vector2 in points:
			uvs.append((point - min_point) / 512.0)
		visual.uv = uvs
	else:
		visual.color = fallback_color
	parent.add_child(visual)


static func _expand_loop(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var count := points.size()
	var result := PackedVector2Array()
	for index in count:
		var prev := points[(index - 1 + count) % count]
		var next := points[(index + 1) % count]
		var tangent := (next - prev).normalized()
		var normal := tangent.rotated(-PI * 0.5)
		var centroid := Vector2.ZERO
		for point: Vector2 in points:
			centroid += point
		centroid /= float(count)
		if normal.dot(centroid - points[index]) < 0.0:
			normal = -normal
		result.append(points[index] + normal * distance)
	return result


static func _add_dashed_centerline(parent: Node, centerline: PackedVector2Array) -> void:
	var line := Line2D.new()
	line.name = "CenterlineDashes"
	line.width = 5.0
	line.default_color = Color("f2ead7", 0.8)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -8
	var count := centerline.size()
	var dash := 0
	var dash_length := 34.0
	var dash_gap := 30.0
	while dash < count - 2:
		var start := centerline[dash]
		var target := centerline[dash + 1]
		var segment_length := start.distance_to(target)
		if segment_length <= dash_gap:
			dash += 1
			continue
		line.add_point(start)
		var ratio := minf(dash_length / segment_length, 1.0)
		line.add_point(start.lerp(target, ratio))
		dash += 1
	parent.add_child(line)


static func _add_edge_line(parent: Node, points: PackedVector2Array, color: Color) -> void:
	var line := Line2D.new()
	line.points = points
	line.closed = true
	line.width = 8.0
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -7
	parent.add_child(line)


static func _add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, scale: Vector2, modulate_value: float = 1.35) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var count := centerline.size()
	var tiles := Node2D.new()
	tiles.name = "TrackSurfaceTiles"
	tiles.z_index = -9
	parent.add_child(tiles)
	for index in range(0, count, 6):
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = centerline[index]
		sprite.rotation = atan2(tangent.y, tangent.x)
		sprite.scale = scale
		sprite.modulate = Color(modulate_value, modulate_value, modulate_value, 0.85)
		tiles.add_child(sprite)


static func _add_floor_tiles(parent: Node, texture_path: String, rect_origin: Vector2, rect_size: Vector2, columns: int, rows: int, scale: Vector2) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var tiles := Node2D.new()
	tiles.name = "FloorTiles"
	tiles.z_index = -21
	parent.add_child(tiles)
	var tile_width := rect_size.x / float(columns)
	var tile_height := rect_size.y / float(rows)
	for column in columns:
		for row in rows:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.position = rect_origin + Vector2(tile_width * (column + 0.5), tile_height * (row + 0.5))
			sprite.scale = Vector2(tile_width / 1024.0, tile_height / 1024.0) * scale * 0.98
			sprite.modulate = Color(1.35, 1.35, 1.35)
			tiles.add_child(sprite)


static func _add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
	var normal := tangent.rotated(PI * 0.5)
	var along := Vector2(tangent.y, -tangent.x)
	if Geometry2D.is_point_in_polygon(start + normal * (HALF_WIDTH + 60.0), corridor):
		normal = -normal
	var banner_center := start - normal * (HALF_WIDTH + 46.0)
	for block in 6:
		var center := banner_center + along * (float(block) - 2.5) * 22.0
		_add_polygon(parent, "BannerBlock%d" % block, PackedVector2Array([
			center - tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 + along * 11.0,
			center - tangent * 22.0 + along * 11.0,
		]), Color("f2ead7") if block % 2 == 0 else Color("c94f38"), -8)


static func _mark_owned(root: Node) -> void:
	for child in root.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_assign_owners(child, root)


static func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owners(child, owner)
