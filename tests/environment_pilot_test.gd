extends SceneTree

const PILOT := preload("res://tools/environment_pilot.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := PILOT.new()
	root.add_child(fixture)
	while not fixture.ready_for_review:
		await process_frame
	var checked := 0
	for theme: String in fixture.THEMES:
		await fixture.show_theme(theme)
		var counts := {}
		for index in fixture.placement_metrics.size():
			var item: Dictionary = fixture.placement_metrics[index]
			counts[item["role"]] = int(counts.get(item["role"], 0)) + 1
			var body: StaticBody2D = item["body"]
			var sprite := body.get_node("Sprite") as Sprite2D
			var visible_size := Vector2(sprite.texture.get_image().get_used_rect().size) * sprite.global_scale.abs()
			var expected_length := float(item["length_mm"])
			var antialias_tolerance := maxf(1.5, expected_length * 0.02)
			_expect(absf(maxf(visible_size.x, visible_size.y) - expected_length) <= antialias_tolerance, theme + ": rendered physical scale drift")
			_expect(is_equal_approx(sprite.scale.x, sprite.scale.y), theme + ": non-uniform prop scaling")
			_expect(sprite.texture.resource_path.get_file().begins_with(theme + "_"), theme + ": cross-theme art")
			_expect(body.find_children("*", "CollisionPolygon2D", false, false).size() == item["outlines"].size(), theme + ": visible solid without collision")
			for polygon: PackedVector2Array in item["outlines"]:
				var nearest := INF
				for route_point: Vector2 in fixture.route_points:
					_expect(not Geometry2D.is_point_in_polygon(route_point, polygon), theme + ": prop covers racing line")
				for point: Vector2 in polygon:
					for route_index in range(1, fixture.route_points.size()):
						nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, fixture.route_points[route_index - 1], fixture.route_points[route_index])))
				var required := float(fixture.manifest["route_width_mm"]) * 0.5 + float(fixture.manifest["route_clearance_mm"])
				_expect(nearest >= required, "%s: %s obscures route (%.1f < %.1f)" % [theme, body.name, nearest, required])
				for other_index in range(index):
					for other: PackedVector2Array in fixture.placement_metrics[other_index]["outlines"]:
						_expect(Geometry2D.intersect_polygons(polygon, other).is_empty(), theme + ": props overlap")
			checked += 1
		_expect(counts.get("hero", 0) == 1, theme + ": expected one focal anchor")
		for role: String in fixture.manifest["roles"]:
			_expect(int(counts.get(role, 0)) >= 1 and int(counts.get(role, 0)) <= int(fixture.manifest["roles"][role]["max_count"]), theme + ": hierarchy/density violation: " + role)
		_expect(is_equal_approx(fixture.camera.zoom.x, 1.12), "pilot must use real slow gameplay zoom")
		var sprite := fixture.vehicle.get_node("VisualRoot/CarSprite") as Sprite2D
		_expect(sprite.scale == Vector2.ONE * 0.5, "unchanged car presentation scale")
	fixture.free()
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("ENVIRONMENT_PILOT_TEST PASS themes=3 props=%d scale hierarchy isolation overlap route_clearance collision" % checked)
	else:
		for failure: String in failures:
			push_error("ENVIRONMENT_PILOT_TEST FAIL " + failure)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
