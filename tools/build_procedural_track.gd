extends SceneTree

## Procedural track builder — generates a painted toy-racing layout from a loop of
## control points (Catmull-Rom spline) swept into a corridor ribbon. The ribbon is
## ONLY a painted surface: collision comes from real-world props — a big themed
## island prop (toolbox / keyboard), room walls, and scattered furniture. Modeled
## on juangallostra/procedural-tracks for the spline + swept corridor + aligned grid.
## Run headless with PC_THEME=workshop|office.

const CHECKPOINT_SCENE := "res://scenes/race/checkpoint.tscn"
const HALF_WIDTH := 125.0
const SAMPLE_COUNT := 260
const GATE_COUNT := 8
const ROOM := Vector2(1750, 1150)

const LAYOUTS := {
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
		"track_texture": "res://assets/textures/imagine/track_asphalt_tile_bright.png",
		"track_tile_modulate": 1.05,
		"floor_texture": "res://assets/textures/imagine/workshop_planks_tile_bright.jpg",
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
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/workshop_toolbox_top_bright.jpg",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
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
		"track_texture": "res://assets/textures/imagine/track_asphalt_tile_bright.png",
		"track_tile_modulate": 1.35,
		"floor_texture": "res://assets/textures/imagine/office_deskmat_tile_bright.jpg",
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
		],
		"island_fill_big": [
			"res://assets/textures/imagine/hose_coil.png",
			"res://assets/textures/imagine/office_keyboard_top_bright.jpg",
		],
		"island_fill_small": [
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		],
		"island_fill_tiny": [
			"res://assets/textures/imagine/paperclip.png",
			"res://assets/textures/kitchen/napkin.png",
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

var _theme: StringName = &"workshop"
var _seed: int = -1


func _init() -> void:
	var env := OS.get_environment("PC_THEME")
	if env in [&"workshop", &"office"]:
		_theme = StringName(env)
	var seed_env := OS.get_environment("PC_SEED")
	if not seed_env.is_empty():
		_seed = int(seed_env)
	call_deferred("_run")


func _run() -> void:
	var spec: Dictionary = LAYOUTS[_theme]
	if _seed >= 0:
		var gen := TrackSeedGen.generate_with_retries(_seed, Rect2(-940, -540, 1880, 1080), {
			"margin": 150.0,
			"min_point_distance": 210.0,
			"max_angle_deg": 80.0,
			"min_self_distance": 280.0,
			"min_loop_length": 1900.0,
		})
		if gen["points"].is_empty():
			push_error("could not generate a valid circuit near seed " + str(_seed))
			quit(1)
			return
		spec = spec.duplicate()
		spec["controls"] = gen["points"]
		spec["seed_obstacles"] = true
		spec["seed"] = int(gen["seed"])
		spec["island_expansion"] = 10.0
		spec.erase("gate_fractions")
		print("SEED_USED ", gen["seed"])
	var root := Node2D.new()
	root.name = String(spec["root_name"])
	root.add_to_group("track")

	var centerline := _sample_centerline(spec["controls"])
	var edges := _corridor_edges(centerline)
	_build_scene(root, spec, centerline, edges)

	_mark_owned(root)
	print("CHILDREN ", str(root.get_children().map(func(child: Node) -> String: return String(child.name))))
	var packed := PackedScene.new()
	packed.pack(root)
	var out_path := OS.get_environment("PC_SCENE_OUT")
	if out_path.is_empty():
		out_path = String(spec["scene"])
	print("SAVE ", ResourceSaver.save(packed, out_path))
	quit(0)


func _sample_centerline(controls: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SAMPLE_COUNT:
		points.append(_catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


func _catmull_rom_closed(points: Array, t: float) -> Vector2:
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


func _corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		left.append(centerline[index] + normal * HALF_WIDTH)
		right.append(centerline[index] - normal * HALF_WIDTH)
	return {"left": left, "right": right, "centerline": centerline}


func _build_scene(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary) -> void:
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]

	# Floor: base fill extends well past the room so the camera never sees a void,
	# themed texture tiles on top at full brightness
	_add_polygon(root, "Floor", _rect_points(Vector2(-600, -500), Vector2(2600, 1700)), spec["floor"], -22)
	_add_polygon(root, "CounterHighlight", _rect_points(Vector2(0, 0), Vector2(1880, 1080)), Color(spec["highlight"], 0.5), -21)
	var floor_texture := String(spec.get("floor_texture", ""))
	if not floor_texture.is_empty():
		_add_floor_tiles(root, floor_texture, Vector2(-600, -500), Vector2(2600, 1700), 6, 4, Vector2(1.0, 1.0))

	# Painted track ribbon (visual only — no collision)
	var corridor := PackedVector2Array()
	corridor.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		corridor.append(right[index])
	var room_rect := _rect_points(Vector2(0, 0), ROOM)
	var clipped_pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(room_rect, corridor)
	var clipped := PackedVector2Array()
	for piece: PackedVector2Array in clipped_pieces:
		if piece.size() > clipped.size():
			clipped = piece
	_add_polygon(root, "TrackRibbon", clipped, spec["asphalt"], -10)
	var track_texture := String(spec.get("track_texture", ""))
	if not track_texture.is_empty():
		_add_centerline_tiles(root, centerline, track_texture, Vector2(0.30, 0.30), float(spec.get("track_tile_modulate", 1.35)))

	# Painted edge lines on BOTH sides of the ribbon so the course reads clearly
	var outer_loop := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	_add_edge_line(root, outer_loop, Color("f2ead7", 0.95))
	_add_dashed_centerline(root, centerline)

	# The big island PROP: real-world object that blocks the corner cut
	var inner_loop := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
	_add_edge_line(root, inner_loop, Color("f2ead7", 0.95))
	_build_island_prop(root, spec, inner_loop, centerline)

	# Room walls (real furniture edges)
	var edge_texture := String(spec.get("edge_texture", "res://assets/textures/kitchen/counter_edge.png"))
	_add_wall(root, "TopWall", Vector2(0, -575), Vector2(2000, 50), edge_texture)
	_add_wall(root, "BottomWall", Vector2(0, 575), Vector2(2000, 50), edge_texture)
	_add_wall(root, "LeftWall", Vector2(-875, 0), Vector2(50, 1200), edge_texture)
	_add_wall(root, "RightWall", Vector2(875, 0), Vector2(50, 1200), edge_texture)

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
	_fill_island(root, spec, inner_loop, corridor)

	# Track obstacles (real props with collision)
	if spec.get("seed_obstacles", false):
		_scatter_seed_props(root, spec, centerline, corridor, gate_samples)
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
		if absf(prop_position.x) > 830.0 or absf(prop_position.y) > 530.0:
			continue
		if not Geometry2D.is_point_in_polygon(prop_position, corridor):
			_add_prop_with_collision(root, prop_position, 30.0, prop_textures[hardware_index % prop_textures.size()])
			hardware_index += 1


	# Themed dressing on the island prop and around it
	if _theme == &"workshop":
		_add_prop(root, "res://assets/textures/kitchen/fork_cartoon.png", Vector2(90, 120), 0.5, 0.2, -8)
		_add_prop(root, "res://assets/textures/kitchen/ruler_plank.png", Vector2(300, 80), 0.6, -0.35, -8)
		_add_prop(root, "res://assets/textures/kitchen/cutting_board.png", Vector2(-260, -120), 0.7, 0.12, -8)
		_add_prop(root, "res://assets/textures/kitchen/toaster_edge.png", Vector2(-460, -40), 0.65, -0.05, -8)
	else:
		_add_sticky_notes(root, Vector2(-430, 60), 0.12)
		_add_sticky_notes(root, Vector2(420, 100), -0.2)
		_add_polygon(root, "PaperSheet", PackedVector2Array([
			Vector2(-300, -150), Vector2(-120, -150), Vector2(-120, -60), Vector2(-300, -60),
		]), Color("f2ead7", 0.55), -12)
		_add_cable_line(root, [Vector2(350, -100), Vector2(480, -60), Vector2(410, -10), Vector2(520, 40)])

	# Start banner above the finish line
	_add_start_banner(root, start, start_tangent, corridor)


func _build_island_prop(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in inner_loop:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	var radius := 90.0

	# Collision: the raw inner loop expanded to the paint edge (no drivable gap)
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

	# Visual: the prop texture stretched over the island shape
	var visual := Polygon2D.new()
	visual.name = "IslandProp"
	visual.z_index = -9
	visual.polygon = expanded
	var prop_texture := String(spec.get("prop_texture", ""))
	var texture := load(prop_texture) as Texture2D if not prop_texture.is_empty() else null
	if texture:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.modulate = Color(1.2, 1.2, 1.2)
		var uvs := PackedVector2Array()
		for point: Vector2 in expanded:
			uvs.append(Vector2(
				(point.x - min_point.x) / maxf(max_point.x - min_point.x, 1.0),
				(point.y - min_point.y) / maxf(max_point.y - min_point.y, 1.0)
			))
		visual.uv = uvs
	else:
		visual.color = spec["island"]
	root.add_child(visual)

	# Clean silhouette: rounded-rect ink outline + kerbs
	var inset := 10.0
	var prop_rect := Rect2(min_point + Vector2(inset, inset), (max_point - min_point) - Vector2(inset, inset) * 2.0)
	var prop_center := prop_rect.get_center()
	var prop_size := prop_rect.size
	var ink := Line2D.new()
	ink.points = _rounded_rect_points(prop_center, prop_size, radius, 6)
	ink.closed = true
	ink.width = 5.0
	ink.default_color = Color("0d0f14", 0.85)
	ink.joint_mode = Line2D.LINE_JOINT_ROUND
	ink.antialiased = true
	ink.z_index = -8
	root.add_child(ink)

	var kerb := Polygon2D.new()
	kerb.name = "Kerbs"
	kerb.z_index = -7
	var kerb_points := PackedVector2Array()
	var kerb_colors := PackedColorArray()
	var kerb_outline := _rounded_rect_points(prop_center, prop_size, radius, 10)
	var kerb_count := kerb_outline.size()
	for index in kerb_count:
		var next := (index + 1) % kerb_count
		var edge_dir := (kerb_outline[next] - kerb_outline[index]).normalized()
		var outward := edge_dir.rotated(-PI * 0.5)
		var probe := prop_center - kerb_outline[index]
		if probe.dot(outward) > 0.0:
			outward = -outward
		if index % 2 == 0:
			var quad := PackedVector2Array([
				kerb_outline[index],
				kerb_outline[next],
				kerb_outline[next] + outward * 26.0,
				kerb_outline[index] + outward * 26.0,
			])
			var block_color := Color("c94f38") if (index / 2) % 2 == 0 else Color("f2ead7")
			kerb_points.append_array(quad)
			for corner in 4:
				kerb_colors.append(block_color)
	root.add_child(kerb)
	kerb.polygon = kerb_points
	kerb.vertex_colors = kerb_colors


func _rounded_rect_points(center: Vector2, size: Vector2, radius: float, corner_segments: int) -> PackedVector2Array:
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


func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


func _arc_lengths(centerline: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array()
	arc.append(0.0)
	var running := 0.0
	for index in range(1, centerline.size()):
		running += centerline[index].distance_to(centerline[index - 1])
		arc.append(running)
	return arc


func _sample_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			var fraction := (target - arc[index - 1]) / maxf(arc[index] - arc[index - 1], 0.001)
			return centerline[index - 1].lerp(centerline[index], fraction)
	return centerline[centerline.size() - 1]


func _tangent_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			return (centerline[index] - centerline[index - 1]).normalized()
	return (centerline[0] - centerline[centerline.size() - 1]).normalized()


func _rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])


func _add_polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color, z: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = z
	parent.add_child(polygon)


func _add_wall(parent: Node, node_name: String, position: Vector2, size: Vector2, edge_texture_path: String) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.position = position
	wall.collision_layer = 2
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.add_child(cs)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = _rect_points(Vector2.ZERO, size)
	visual.color = Color("0e1524")
	wall.add_child(visual)
	var edge_texture := load(edge_texture_path) as Texture2D
	if edge_texture:
		var horizontal := size.x > size.y
		var edge_length := maxf(size.x, size.y)
		var tile_count := maxi(1, int(ceil(edge_length / 1024.0)))
		for tile in tile_count:
			var strip := Sprite2D.new()
			strip.name = "EdgeStrip"
			strip.texture = edge_texture
			strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var offset := (float(tile) - float(tile_count - 1) * 0.5) * (edge_length / float(tile_count))
			strip.position = Vector2(offset, 0.0) if horizontal else Vector2(0.0, offset)
			strip.rotation = 0.0 if horizontal else PI * 0.5
			strip.scale = Vector2(edge_length / (1024.0 * float(tile_count)), size.y / 220.0) if horizontal else Vector2(edge_length / (1024.0 * float(tile_count)), size.x / 220.0)
			wall.add_child(strip)


func _add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float) -> void:
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


func _add_grid(parent: Node, node_name: String, rotation: float, positions: Array) -> void:
	var grid := Node2D.new()
	grid.name = node_name
	parent.add_child(grid)
	for index in positions.size():
		var marker := Node2D.new()
		marker.name = str(index)
		marker.position = positions[index]
		marker.rotation = rotation
		grid.add_child(marker)


func _scatter_seed_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, corridor: PackedVector2Array, gate_samples: PackedVector2Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var textures: Array = spec.get("scatter_textures", [])
	if textures.is_empty():
		return
	var count := centerline.size()

	var clear_of_gates := Callable(self, "_seed_clear_of_gates").bind(gate_samples)

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
		var candidate := sample + normal * (55.0 if rng.randf() < 0.5 else -55.0)
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
		_add_obstacle(root, "SeedCorridor", position, 34.0, String(textures[rng.randi_range(0, textures.size() - 1)]))

	# b) apron clutter outside the loop
	var apron_props := PackedVector2Array()
	for attempt in 400:
		var candidate := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
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


func _fill_island(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, corridor: PackedVector2Array) -> void:
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
	var radius := 36.0
	var dbg_total := 0
	var dbg_in := 0
	var dbg_corridor := 0
	var dbg_circle := 0
	var dbg_ok := 0
	for row in range(int(ceil((max_point.y - min_point.y) / pitch)) + 1):
		for column in range(int(ceil((max_point.x - min_point.x) / pitch)) + 1):
			var center := Vector2(
				min_point.x + float(column) * pitch + rng.randf_range(-12.0, 12.0),
				min_point.y + float(row) * pitch + rng.randf_range(-12.0, 12.0))
			dbg_total += 1
			if not Geometry2D.is_point_in_polygon(center, inner_loop):
				dbg_in += 1
				continue
			if Geometry2D.is_point_in_polygon(center, corridor):
				dbg_corridor += 1
				continue
			var circle_clear := true
			for sample in 8:
				var angle := TAU * float(sample) / 8.0
				if Geometry2D.is_point_in_polygon(center + Vector2(cos(angle), sin(angle)) * (radius + 24.0), corridor):
					circle_clear = false
					break
			if not circle_clear:
				dbg_circle += 1
				continue
			dbg_ok += 1
			_add_fill_prop(root, center, radius, String(textures[rng.randi_range(0, textures.size() - 1)]), rng.randf_range(0.0, TAU))


func _add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "IslandFill"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 4
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
		sprite.scale = Vector2.ONE * (radius * 2.2 / maxf(longest, 1.0))
		prop.add_child(sprite)


func _seed_clear_of_gates(point: Vector2, gate_samples: PackedVector2Array) -> bool:
	for gate: Vector2 in gate_samples:
		if point.distance_to(gate) < 160.0:
			return false
	return true


func _point_in_loop(point: Vector2, loop: PackedVector2Array) -> bool:
	var inside := false
	var count := loop.size()
	for index in count:
		var a := loop[index]
		var b := loop[(index + 1) % count]
		if ((a.y > point.y) != (b.y > point.y)) and (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
	return inside


func _add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = node_name
	obstacle.position = position
	obstacle.collision_layer = 2
	parent.add_child(obstacle)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	obstacle.add_child(cs)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (radius * 2.4 / maxf(longest, 1.0))
		obstacle.add_child(sprite)


func _add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
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


func _add_prop(parent: Node, texture_path: String, position: Vector2, scale: float, rotation: float, z: int) -> void:
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


func _add_sticky_notes(parent: Node, center: Vector2, rotation: float) -> void:
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


func _add_cable_line(parent: Node, points: Array) -> void:
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


func _add_dashed_centerline(parent: Node, centerline: PackedVector2Array) -> void:
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


func _add_edge_line(parent: Node, points: PackedVector2Array, color: Color) -> void:
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


func _add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, scale: Vector2, modulate_value: float = 1.35) -> void:
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
		sprite.modulate = Color(modulate_value, modulate_value, modulate_value)
		tiles.add_child(sprite)


func _add_floor_tiles(parent: Node, texture_path: String, rect_origin: Vector2, rect_size: Vector2, columns: int, rows: int, scale: Vector2) -> void:
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


func _add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
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


func _mark_owned(root: Node) -> void:
	for child in root.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_assign_owners(child, root)


func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owners(child, owner)
