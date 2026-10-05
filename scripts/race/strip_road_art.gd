extends RefCounted

const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const COURSE := preload("res://scripts/race/handmade_course_materials.gd")
const SAMPLER := preload("res://scripts/race/strip/strip_route_sampler.gd")
const ROAD := preload("res://scripts/race/strip/strip_road_rules.gd")
const CLOTH_TEXTURE := "res://assets/textures/imagine/track_cloth.png"
const SELVEDGE := 10.0
const BINDING_WIDTH := 5.0
const HEM_WIDTH := 8.0
const DASH_LENGTH := 45.0
const DASH_SPACING := 135.0
const STITCH_LENGTH := 6.0
const STITCH_SPACING := 22.0
const MARK_WIDTH := 2.5
const CENTER_WIDTH := 4.0
const CENTER_GAP := 10.0
const THRESHOLD_WIDTH := 16.0
const ARROW_SPACING := 1800.0
const ARROW_SIZE := Vector2(22.0, 42.0)


static func build(root: Node2D, prepared: Dictionary) -> void:
	var spec: Dictionary = prepared["spec"]
	var identity: Dictionary = spec["surface_identity"]
	var course: Dictionary = identity["course"]
	var line: PackedVector2Array = prepared["centerline"]
	var half_width := float(prepared["strip_half_width"])
	var profile: Dictionary = identity["floor"].duplicate(true)
	profile.merge({"id": "strip_woven_runner", "pattern": int(SURFACES.catalog()["patterns"]["weave"]), "texture": CLOTH_TEXTURE, "cell_mm": Vector2(6.0, 6.0), "line_mm": 0.45, "contrast": 0.06, "angle": 0.0}, true)
	profile["base_color"] = (profile["base_color"] as Color).lerp(course["edge_color"], 0.35)
	profile["alternate_color"] = (profile["base_color"] as Color).darkened(0.12)
	profile["seam_color"] = (profile["base_color"] as Color).darkened(0.20)
	var cloth := SURFACES._material(profile)
	var shadow := _line(root, "RunnerContactShadow", line, (half_width + SELVEDGE) * 2.0 + 3.0, Color(0.12, 0.10, 0.08, 0.16), -13)
	shadow.position = Vector2(2.0, 2.0)
	var runner := _line(root, "WovenRunner", line, (half_width + SELVEDGE) * 2.0, Color.WHITE, -12)
	runner.material = cloth
	runner.set_meta("material_profile", profile["id"])
	# The race paint shader is unchanged; only its substrate is cloth rather
	# than the surrounding counter. Weave continues through the printed road.
	COURSE.apply(root, course, cloth)
	var road := root.get_node("TrackSurface") as Line2D
	road.z_index = -11
	road.set_meta("substrate_profile", profile["id"])
	var sampler := SAMPLER.new()
	sampler.configure(line)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["material_seed"]) ^ 0x48454d
	for side in [-1.0, 1.0]:
		var points := PackedVector2Array()
		for index in line.size():
			var tangent := (line[mini(line.size() - 1, index + 1)] - line[maxi(0, index - 1)]).normalized()
			points.append(line[index] + tangent.rotated(PI * 0.5) * side * (half_width + SELVEDGE - BINDING_WIDTH * 0.5))
		var binding_color := (profile["seam_color"] as Color).lerp(course["edge_color"], rng.randf_range(0.10, 0.30))
		_line(root, "RunnerBindingLeft" if side < 0 else "RunnerBindingRight", points, BINDING_WIDTH, binding_color, -10)
		_dashes(root, sampler, "RunnerStitchLeft" if side < 0 else "RunnerStitchRight", side * (half_width + SELVEDGE * 0.5), STITCH_LENGTH, STITCH_SPACING, 1.0, Color(binding_color, 0.6))
	for side in [-1.0, 1.0]:
		var divider := PackedVector2Array()
		for index in line.size():
			var tangent := (line[mini(line.size() - 1, index + 1)] - line[maxi(0, index - 1)]).normalized()
			divider.append(line[index] + tangent.rotated(PI * 0.5) * side * CENTER_GAP * 0.5)
		_line(root, "CenterDividerLeft" if side < 0 else "CenterDividerRight", divider, CENTER_WIDTH, Color(course["edge_color"], 0.88), -8)
		_dashes(root, sampler, "SouthboundLaneDashes" if side < 0 else "NorthboundLaneDashes", side * ROAD.LANE_WIDTH, DASH_LENGTH, DASH_SPACING, MARK_WIDTH, Color(course["edge_color"], 0.65))
	_arrows(root, sampler, Color(course["edge_color"], 0.55))


static func build_landmarks(root: Node2D, prepared: Dictionary) -> void:
	var sampler := SAMPLER.new()
	sampler.configure(prepared["centerline"])
	var half_width := float(prepared["strip_half_width"])
	for endpoint in 2:
		var region := root.get_node("StripRoom%d" % endpoint)
		var cloth: ShaderMaterial = region.get_node("WovenRunner").material
		var color: Color = region.get_node("RunnerBindingLeft").default_color
		var sample: Dictionary = sampler.sample(0.0 if endpoint == 0 else sampler.length())
		_hem(root, "StartCap" if endpoint == 0 else "FinishCap", sample, half_width + SELVEDGE, cloth, color)
	var course: Dictionary = prepared["strip_regions"][0]["spec"]["surface_identity"]["course"]
	var grid: Dictionary = prepared["strip_grid"]
	for key: String in grid:
		var transform: Transform2D = grid[key]
		var bracket := PackedVector2Array([Vector2(-23, -18), Vector2(-23, 31), Vector2(23, 31), Vector2(23, -18)])
		_line(root, "PrintedGrid" + key.capitalize(), transform * bracket, MARK_WIDTH, Color(course["edge_color"], 0.62), -7)
	var start_arc := 0.0
	for transform: Transform2D in grid.values():
		start_arc = maxf(start_arc, float(sampler.project(transform.origin)["arc"]))
	var start: Dictionary = sampler.sample(start_arc + DASH_SPACING)
	TrackBuilderCore._add_finish_checker(root, start["pos"], start["dir"], half_width)
	var seam: Dictionary = prepared["strip_theme_switch"]
	var across := Vector2.RIGHT.rotated(float(seam["rotation"])) * (half_width + SELVEDGE)
	var position: Vector2 = seam["position"]
	var threshold := _line(root, "RoomThreshold", PackedVector2Array([position - across, position + across]), THRESHOLD_WIDTH, Color(course["edge_color"], 0.85), -7)
	threshold.set_meta("theme_a", prepared["theme"])
	threshold.set_meta("theme_b", prepared["theme_b"])
	threshold.set_meta("arc", seam["arc"])


static func _line(parent: Node, node_name: String, points: PackedVector2Array, width: float, color: Color, z: int) -> Line2D:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = z
	TrackBuilderCore._mark_flat_visual(line, CLOTH_TEXTURE, &"runner_print")
	parent.add_child(line)
	return line


static func _dashes(parent: Node, sampler: RefCounted, node_name: String, offset: float, length: float, spacing: float, width: float, color: Color) -> void:
	# One mesh per marking family, rather than thousands of individual nodes.
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for index in floori(sampler.length() / spacing):
		var start: Dictionary = sampler.sample(index * spacing)
		var end: Dictionary = sampler.sample(index * spacing + length)
		var a: Vector2 = start["pos"] + start["perp"] * offset
		var b: Vector2 = end["pos"] + end["perp"] * offset
		var normal := (b - a).orthogonal().normalized() * width * 0.5
		for point in [a - normal, a + normal, b + normal, a - normal, b + normal, b - normal]:
			vertices.append(point)
			colors.append(color)
	_paint_mesh(parent, node_name, vertices, colors)


static func _arrows(parent: Node, sampler: RefCounted, color: Color) -> void:
	var outline := PackedVector2Array([Vector2(0.0, -0.5), Vector2(0.5, -0.1), Vector2(0.16, -0.1), Vector2(0.16, 0.5), Vector2(-0.16, 0.5), Vector2(-0.16, -0.1), Vector2(-0.5, -0.1)])
	var triangles := Geometry2D.triangulate_polygon(outline)
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for slot in floori(sampler.length() / ARROW_SPACING):
		var sample: Dictionary = sampler.sample((slot + 0.5) * ARROW_SPACING)
		for lane: int in ROAD.LANES:
			var angle := ((sample["dir"] as Vector2) * ROAD.direction(lane)).angle() + PI * 0.5
			var center: Vector2 = sample["pos"] + sample["perp"] * ROAD.fraction(lane) * ROAD.HALF_WIDTH
			for index in triangles:
				vertices.append(center + (outline[index] * ARROW_SIZE).rotated(angle))
				colors.append(color)
	_paint_mesh(parent, "PrintedDirectionArrows", vertices, colors)


static func _paint_mesh(parent: Node, node_name: String, vertices: PackedVector2Array, colors: PackedColorArray) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance2D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.z_index = -8
	TrackBuilderCore._mark_flat_visual(instance, "", &"runner_print")
	parent.add_child(instance)


static func _hem(parent: Node, node_name: String, sample: Dictionary, half_width: float, cloth: ShaderMaterial, color: Color) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = sample["pos"]
	body.rotation = (sample["perp"] as Vector2).angle()
	body.collision_layer = 2
	TrackBuilderCore._mark_solid_body(body, CLOTH_TEXTURE, &"runner_fold")
	parent.add_child(body)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(half_width * 2.0, HEM_WIDTH)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := Polygon2D.new()
	visual.name = "FoldedFabric"
	visual.polygon = TrackBuilderCore._rect_points(Vector2.ZERO, shape.size)
	visual.color = color
	visual.material = cloth
	TrackBuilderCore._mark_solid_visual(visual, CLOTH_TEXTURE, &"runner_fold")
	body.add_child(visual)
	TrackBuilderCore._record_shape_probe_points(body, Vector2.ZERO, shape.size, &"rect")
