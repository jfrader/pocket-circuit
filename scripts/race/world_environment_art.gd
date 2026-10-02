class_name WorldEnvironmentArt
extends RefCounted

const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const GRIP_SHADER := preload("res://assets/shaders/grip_surface.gdshader")
const GRIP_EDGE_FEATHER_MM := 18.0
const GRIP_MAX_STAMPS := 6
const GRIP_FIT_ATTEMPTS := 48
const GRIP_STAMP_GAP_MM := 6.0
const GRIP_MIN_RADIUS_MM := 8.0
const GRIP_STAMP_OPACITY := 0.72
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
	run_modes.resize(WorldEnvironmentPlan.SECTOR_COUNT)
	run_modes.fill(&"none")
	for placement: Dictionary in plan["placements"]:
		var asset := CATALOG.get_asset(placement["asset_id"])
		var node := render_prop(containers[String(placement["role"])], asset, placement)
		if placement["role"] == "focal":
			root.set_meta("environment_focal", node.position)
		elif placement["role"] == "boundary":
			var closest := TrackBuilderCore._closest_point_on_loop(node.position, centerline)
			var run := mini(WorldEnvironmentPlan.SECTOR_COUNT - 1, int(float(closest["index"]) / centerline.size() * WorldEnvironmentPlan.SECTOR_COUNT))
			var side := &"outer" if placement["zone"] == "apron" else &"inner"
			run_modes[run] = side if run_modes[run] == &"none" or run_modes[run] == side else &"both"
			node.set_meta("boundary_kind", &"partial_section")
			node.set_meta("run_index", run)
			node.set_meta("boundary_side", side)
			if placement.has("boundary_run_id"):
				node.set_meta("boundary_run_id",placement["boundary_run_id"])
				node.set_meta("boundary_member",placement["boundary_member"])
		if stage.is_valid():
			await stage.call("Placing room objects")
	root.set_meta("environment_diagnostics", plan["diagnostics"])
	root.set_meta("environment_placements", plan["placements"])
	root.set_meta("boundary_runs", plan.get("boundary_runs",[]))
	boundary.set_meta("run_modes", run_modes)
	boundary.set_meta("empty_run_count", run_modes.count(&"none"))
	boundary.set_meta("open_exit", plan["diagnostics"].get("open_exit", PackedVector2Array()))
	var gates := TrackBuilderCore._layout_gate_samples(centerline, spec)
	var gameplay := TrackBuilderCore._analyze_track_moments(centerline, gates, spec)
	TrackBuilderStory.build_gameplay_moments(root, gameplay, 0)
	TrackBuilderCore._build_finish_moments(moments, centerline)
	TrackBuilderDressing.build_generated_surfaces(root, moments, spec["story_kit"], spec, gameplay, centerline, gates, false)
	var surfaces: Array = root.get_meta("generated_surfaces", [])
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var asset := CATALOG.for_path(String(surface["decal"]))
		if asset.is_empty():
			continue
		var name := "SurfaceRegion" + str(surface_index)
		_draw_grip_surface(root, name, asset, surface["points"], int(spec.get("material_seed", 0)), spec.get("surface_art_exclusions", []))
		if stage.is_valid():
			await stage.call("Preparing grip surfaces")
	if stage.is_valid():
		await stage.call("Preparing course material")
	SURFACES.apply(root, spec["surface_identity"])


static func _draw_grip_surface(root: Node2D, name: String, asset: Dictionary, polygon: PackedVector2Array, seed_value: int, exclusions: Array[PackedVector2Array] = []) -> void:
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
	var region := Node2D.new()
	region.name = name
	region.material = material
	region.z_index = -6
	root.add_child(region)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(seed_value, name + String(asset["id"]))
	var texture := load(asset["texture_path"]) as Texture2D
	var used := TrackBuilderCore._texture_opaque_rect(texture)
	var scale := TrackBuilderCore.PROP_SCALE.sprite_scale(texture, used, float(asset["length_mm"]))
	var nominal_radius := used.size.length() * scale * 0.5
	var stamps := _grip_stamp_layout(polygon, nominal_radius, mini(int(asset["max_repeats"]), GRIP_MAX_STAMPS), rng, exclusions)
	for index in stamps.size():
		var stamp: Dictionary = stamps[index]
		var sprite := Sprite2D.new()
		sprite.name = name + "Paint" + str(index)
		sprite.rotation = rng.randf_range(-PI, PI)
		sprite.scale = Vector2.ONE * scale * float(stamp["radius"]) / nominal_radius
		sprite.position = stamp["position"] - ((used.get_center() - texture.get_size() * 0.5) * sprite.scale).rotated(sprite.rotation)
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.use_parent_material = true
		sprite.modulate.a = GRIP_STAMP_OPACITY
		TrackBuilderCore._mark_flat_visual(sprite, asset["texture_path"], &"surface_decal")
		region.add_child(sprite)


static func _grip_stamp_layout(polygon: PackedVector2Array, nominal_radius: float, count: int, rng: RandomNumberGenerator, exclusions: Array[PackedVector2Array] = []) -> Array[Dictionary]:
	var bounds := TrackBuilderCore._polygon_bounds_rect(polygon)
	var nearby: Array[PackedVector2Array] = []
	for exclusion: PackedVector2Array in exclusions:
		if bounds.grow(GRIP_STAMP_GAP_MM).intersects(TrackBuilderCore._polygon_bounds_rect(exclusion)):
			nearby.append(exclusion)
	var stamps: Array[Dictionary] = []
	for index in count:
		var best := {}
		var best_radius := GRIP_MIN_RADIUS_MM
		for attempt in GRIP_FIT_ATTEMPTS:
			var point := bounds.get_center() if index == 0 and attempt == 0 else bounds.position + bounds.size * Vector2(rng.randf(), rng.randf())
			if not Geometry2D.is_point_in_polygon(point, polygon):
				continue
			var radius := nominal_radius
			for edge in polygon.size():
				var closest := Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()])
				radius = minf(radius, point.distance_to(closest) - GRIP_STAMP_GAP_MM)
			for exclusion: PackedVector2Array in nearby:
				if Geometry2D.is_point_in_polygon(point, exclusion):
					radius = 0.0
					break
				for edge in exclusion.size():
					var closest := Geometry2D.get_closest_point_to_segment(point, exclusion[edge], exclusion[(edge + 1) % exclusion.size()])
					radius = minf(radius, point.distance_to(closest) - GRIP_STAMP_GAP_MM)
			for other: Dictionary in stamps:
				radius = minf(radius, point.distance_to(other["position"]) - float(other["radius"]) - GRIP_STAMP_GAP_MM)
			if radius > best_radius:
				best_radius = radius
				best = {"position": point, "radius": radius}
		if best.is_empty():
			break
		stamps.append(best)
	return stamps
