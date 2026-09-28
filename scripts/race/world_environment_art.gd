class_name WorldEnvironmentArt
extends RefCounted

const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const GRIP_SHADER := preload("res://assets/shaders/grip_surface.gdshader")
const GRIP_EDGE_FEATHER_MM := 18.0
const ROLE_CONTAINERS := {"focal":"IslandStory","support":"ObjectLine","micro":"MicroDetails","boundary":"SparseDelimiter","ground":"GroundSections","decal":"FloorDetails"}


static func render_prop(parent: Node2D, asset: Dictionary, placement: Dictionary) -> Node2D:
	var path := String(asset["texture_path"])
	var role := StringName(placement["role"])
	var name := String(asset["id"]).to_pascal_case() + str(parent.get_child_count())
	var node: Node2D
	if asset["collision"] != "flat":
		TrackBuilderCore._add_generated_prop(parent, name, placement["position"], path, float(placement["rotation"]), role, &"unique" if role == &"focal" else &"few", parent.get_child_count())
		node = parent.get_node(name)
	else:
		node = Node2D.new()
		node.name = name
		node.position = placement["position"]
		node.rotation = float(placement["rotation"])
		parent.add_child(node)
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = load(path) as Texture2D
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * TrackBuilderCore.PROP_SCALE.sprite_scale(sprite.texture, TrackBuilderCore._texture_opaque_rect(sprite.texture), float(asset["length_mm"]))
		sprite.modulate.a = float(asset.get("opacity", 1.0))
		TrackBuilderCore._mark_flat_visual(sprite, path, role)
		node.add_child(sprite)
		node.z_index = -10 if role == &"decal" else -4
	node.set_meta("environment_asset_id", asset["id"])
	node.set_meta("asset_path", path)
	node.set_meta("environment_role", role)
	node.set_meta("physical_dimensions_mm", asset["dimensions_mm"])
	return node


static func compose(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, stage: Callable) -> void:
	var theme := StringName(spec["environment_theme"])
	var plan: Dictionary = spec["environment_plan"]
	var moments := Node2D.new()
	moments.name = "GeneratedMoments"
	root.add_child(moments)
	var containers := {}
	for role: String in ROLE_CONTAINERS:
		var container := Node2D.new()
		container.name = ROLE_CONTAINERS[role]
		moments.add_child(container)
		containers[role] = container
	var boundary := Node2D.new()
	boundary.name = "GeneratedOuterBoundaryVisuals"
	root.add_child(boundary)
	containers["boundary"] = boundary
	var run_modes: Array[StringName] = []
	run_modes.resize(8)
	run_modes.fill(&"none")
	for placement: Dictionary in plan["placements"]:
		var asset := CATALOG.get_asset(placement["asset_id"])
		var node := render_prop(containers[String(placement["role"])], asset, placement)
		if placement["role"] == "focal":
			root.set_meta("environment_focal", node.position)
		elif placement["role"] == "boundary":
			var closest := TrackBuilderCore._closest_point_on_loop(node.position, centerline)
			var run := mini(7, int(float(closest["index"]) / centerline.size() * 8.0))
			run_modes[run] = &"outer" if placement["zone"] == "apron" else &"inner"
			node.set_meta("boundary_kind", &"partial_section")
			node.set_meta("run_index", run)
			node.set_meta("boundary_side", run_modes[run])
		if stage.is_valid():
			await stage.call("Placing room objects")
	root.set_meta("environment_diagnostics", plan["diagnostics"])
	root.set_meta("environment_placements", plan["placements"])
	boundary.set_meta("run_modes", run_modes)
	boundary.set_meta("empty_run_count", run_modes.count(&"none"))
	var gates := TrackBuilderCore._layout_gate_samples(centerline, spec)
	var gameplay := TrackBuilderCore._analyze_track_moments(centerline, gates)
	TrackBuilderStory.build_gameplay_moments(root, moments, spec, gameplay, centerline, 0)
	TrackBuilderCore._build_finish_moments(moments, centerline)
	TrackBuilderDressing.build_generated_surfaces(root, moments, spec["story_kit"], spec, gameplay, centerline, gates, false)
	for surface: Dictionary in root.get_meta("generated_surfaces", []):
		var asset := CATALOG.for_path(String(surface["decal"]))
		if asset.is_empty():
			continue
		var name := "SurfaceRegion" + str(root.get_child_count())
		_draw_grip_surface(root, name, asset, surface["points"], int(spec.get("material_seed", 0)))
		if stage.is_valid():
			await stage.call("Preparing grip surfaces")
	var grain := SURFACES.apply(root, spec["surface_identity"])
	if stage.is_valid() and grain != null and grain.get_image() == null:
		await stage.call("Preparing course material")
		if grain.get_image() == null:
			await grain.changed


static func _draw_grip_surface(root: Node2D, name: String, asset: Dictionary, polygon: PackedVector2Array, seed_value: int) -> void:
	var points := polygon.duplicate()
	if points.size() > 64:
		push_error("Grip contour exceeds shader boundary capacity")
		return
	var count := points.size()
	points.resize(64)
	var material := ShaderMaterial.new()
	material.shader = GRIP_SHADER
	material.set_shader_parameter("boundary", points)
	material.set_shader_parameter("boundary_count", count)
	material.set_shader_parameter("feather_mm", GRIP_EDGE_FEATHER_MM)
	var tint := Color(String(asset.get("average_color", "#c5b594")))
	tint.a = 0.12
	var underlay := material.duplicate() as ShaderMaterial
	underlay.set_shader_parameter("underlay", true)
	underlay.set_shader_parameter("surface_color", tint)
	TrackBuilderCore._add_polygon(root, name, polygon, Color.WHITE, -7)
	var visual := root.get_node(name) as Polygon2D
	visual.material = underlay
	TrackBuilderCore._mark_flat_visual(visual, asset["texture_path"], &"surface_decal")
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(seed_value, name + String(asset["id"]))
	var bounds := TrackBuilderCore._polygon_bounds_rect(polygon)
	var texture := load(asset["texture_path"]) as Texture2D
	var scale := TrackBuilderCore.PROP_SCALE.sprite_scale(texture, TrackBuilderCore._texture_opaque_rect(texture), float(asset["length_mm"]))
	for index in mini(int(asset["max_repeats"]), 6):
		var point := bounds.get_center()
		for attempt in 24:
			var candidate := bounds.position + bounds.size * Vector2(rng.randf(), rng.randf())
			if Geometry2D.is_point_in_polygon(candidate, polygon):
				point = candidate
				break
		var sprite := Sprite2D.new()
		sprite.name = name + "Paint" + str(index)
		sprite.position = point
		sprite.rotation = rng.randf_range(-PI, PI)
		sprite.scale = Vector2.ONE * scale
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.material = material
		sprite.modulate.a = 0.72
		sprite.z_index = -6
		TrackBuilderCore._mark_flat_visual(sprite, asset["texture_path"], &"surface_decal")
		root.add_child(sprite)
