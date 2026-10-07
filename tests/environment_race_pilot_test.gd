extends SceneTree

const SCENE := preload("res://tools/environment_race_pilot.tscn")
const CORE := preload("res://scripts/race/track_builder_core.gd")
const ART := preload("res://tools/environment_pilot_props.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for theme: String in ["kitchen", "workshop", "office"]:
		var fixture := SCENE.instantiate()
		var race := fixture.get_node("Race")
		race.set("pilot_theme", theme)
		race.set("capture_mode", true)
		race.set("production_environment", false)
		root.add_child(fixture)
		var preparing_player := get_first_node_in_group("player_vehicle") as RigidBody2D
		if not _expect(preparing_player != null and preparing_player.freeze and bool(preparing_player.get("controls_locked")), theme + ": player must remain frozen and ignore input while the race is prepared"): return
		var deadline := Time.get_ticks_msec() + 60000
		while not bool(race.get("pilot_ready")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not _expect(bool(race.get("pilot_ready")), theme + ": native race failed to become ready"): return
		if not bool(race.get("pilot_ready")):
			fixture.free()
			break
		var track := race.get_node("Track") as Node2D
		var manager := race.get_node("RaceManager")
		if not _expect(manager.call("get_rankings").size() == 4, theme + ": actual four-racer field is missing"): return
		var gates := 0
		for child: Node in track.get_children():
			if child.is_in_group("track_checkpoints"):
				gates += 1
		if not _expect(gates == CORE.GATE_COUNT, theme + ": generated race gates changed"): return
		if not _expect(track.has_node("InnerBarrier/BoundaryCollision"), theme + ": physical island missing"): return
		if not _expect(track.has_node("RacingLine") and track.has_node("GridForward"), theme + ": route/grid missing"): return
		var primary_keys := {}
		var hero_count := 0
		for item: Dictionary in race.get("pilot_art").placements:
			var body: Node2D = item["body"]
			if body.get_meta("cluster_index", -1) == 0:
				primary_keys[String(item["asset_key"])] = true
			if item["asset_key"] == "hero":
				hero_count += 1
			var sprite := body.get_node("Sprite") as Sprite2D
			var used_size := Vector2(sprite.texture.get_image().get_used_rect().size) * sprite.global_scale.abs()
			var length := float(item["length_mm"])
			if not _expect(absf(maxf(used_size.x, used_size.y) - length) < maxf(1.5, length * 0.02), theme + ": rendered scale mismatch"): return
			if not _expect(body is StaticBody2D or bool(item["flat"]), theme + ": raised art lacks physical collision"): return
			if bool(item["flat"]):
				for barrier: Node in track.find_children("*", "StaticBody2D", true, false):
					if not barrier.has_meta("collision_boundary_polygon"):
						continue
					var blocked: PackedVector2Array = barrier.get_meta("collision_boundary_polygon")
					for outline: PackedVector2Array in item["outlines"]:
						var touches := not Geometry2D.intersect_polygons(outline, blocked).is_empty()
						var extends_outside := not Geometry2D.clip_polygons(outline, blocked).is_empty()
						if not _expect(not (touches and extends_outside), theme + ": cloth/paper conceals a solid rim"): return
		if not _expect(hero_count == 1, theme + ": expected exactly one focal hero"): return
		if not _expect(primary_keys.has("hero") and primary_keys.has("medium") and primary_keys.has("ground") and primary_keys.size() >= 5, theme + ": focal arrangement collapsed into isolated objects"): return
		for node: Node in track.find_children("*", "CanvasItem", true, false):
			var texture: Texture2D = node.texture if node is Sprite2D or node is Polygon2D or node is Line2D else null
			if texture:
				var registered := WorldEnvironmentCatalog.for_path(texture.resource_path)
				if not _expect(texture.resource_path.begins_with(ART.TEXTURES) or registered.get("style", "") == WorldEnvironmentCatalog.CONTRACT, theme + ": unregistered/rejected art remains active: " + texture.resource_path): return
		var presenter := race.get("_track_variant_presenter") as TrackVariantPresenter
		if not _expect(presenter.surface_zones.size() == 2, theme + ": visible grip surfaces are not active"): return
		var save_before: Dictionary = root.get_node("App").get("_save_data").duplicate(true)
		race.call("_attempt_result_commit", [{"position": 4, "driver_name": "Pilot tester", "time": 1.0, "dnf": true, "finished": false}])
		if not _expect("DNF" in String(race.get("_results_label").text), theme + ": unfinished racers must not receive a finish time"): return
		if not _expect(save_before == root.get_node("App").get("_save_data"), theme + ": pilot results must not alter campaign progress"): return
		print("RACE_PILOT_CHECK theme=%s placements=%d primary=%s frame_gap=%.1f phase=%s" % [theme, int(track.get_meta("pilot_placement_count")), primary_keys.keys(), float(race.get("pilot_frame_gap_ms")), race.get("pilot_slowest_phase")])
		fixture.free()
		await process_frame
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	for failure: String in failures:
		push_error("ENVIRONMENT_RACE_PILOT_TEST FAIL " + failure)
	if failures.is_empty():
		print("ENVIRONMENT_RACE_PILOT_TEST PASS native_race_hud_field_geometry_fresh_art_scale_hierarchy_surfaces")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
		return false
	return true
