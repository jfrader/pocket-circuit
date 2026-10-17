extends SceneTree

const SCENE := preload("res://scripts/ui/run_board_scene.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const BOARD_IDENTITY := preload("res://scripts/ui/run_board_identity.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const STOP_CAR := preload("res://scripts/ui/run_stop_car.gd")
const INTRO := preload("res://scripts/ui/run_board_intro.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const MAP_VIEW := preload("res://scripts/ui/run_map_view.gd")
const BOARD_TOKEN := preload("res://scripts/ui/run_board_token.gd")

class EmptyAssignments extends RunSession:
	func opponents_for_node(_node_id: String) -> Dictionary:
		return {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	if not await _test_intro(app, shell):
		return
	if not _expect(bool(app.call("update_setting", "reduced_motion", false)), "material-motion fixture enables ambient motion"):
		return
	var session: RunSession = app.call("start_run", 2426001)
	var session_snapshot := RunSession.serialize(session)
	var surfaces: Array[String] = []
	for act: int in SCENE.ROOM_NAMES:
		session.current_map.act = act
		shell.call("show_run_board")
		await process_frame
		await process_frame
		await create_timer(0.3).timeout
		var table := shell.find_child("RunTabletop", true, false) as Control
		if not _expect(table != null and table.get("act") == act, "the tabletop follows the act"):
			return
		if not _expect(table.get_node_or_null("Lamplight") != null, "the table has its warm-to-night light layer"):
			return
		var dressing := table.get_node("RoomDressing")
		if not _expect(dressing.get_child_count() == 18, "table dressing uses a bounded seeded set of painted props"):
			return
		for prop: Node in dressing.get_children():
			if not _expect(MATERIALS.ROOM_DRESSING[act].has((prop as TextureRect).texture), "painted crumbs and debris belong to the current room"):
				return
		if not _expect(table.get_node("BeamDust").get_child_count() == 3 and table.get("_lamp_pulse") != null, "lamp beam has three restrained motes and a warmth pulse"):
			return
		for mote: Node in table.get_node("BeamDust").get_children():
			if not _expect((mote as TextureRect).size.x <= 8 and (mote as TextureRect).size.y <= 8, "painted dust remains tiny rather than inheriting the source texture's minimum size"):
				return
		if not _expect(MATERIALS.chalk_brush() == MATERIALS.chalk_brush() and MATERIALS.chalk_brush().get_image().get_format() == Image.FORMAT_RGBA8, "chalk breakup is baked once with real alpha"):
			return
		var surface: Texture2D = SCENE.SURFACES[act]
		if not _expect(not surfaces.has(surface.resource_path), "each room uses a distinct existing material"):
			return
		surfaces.append(surface.resource_path)
		var board := shell.find_child("RunBoard", true, false) as Control
		var expected_map := Rect2(24, 16, 896, 624)
		if not _expect(board.get_global_rect().is_equal_approx(expected_map), "active map occupies the intended hero rect (24,16,896,624)"):
			return
		var active_detail := shell.find_child("RunDetail", true, false) as Control
		var slot := shell.find_child("RunDetailSlot", true, false) as Control
		if not _expect(is_equal_approx(slot.get_global_rect().position.x, 944) and is_equal_approx(slot.size.x, 312) and is_equal_approx(active_detail.get_global_rect().position.x, 968) and is_equal_approx(active_detail.size.x, 264) and active_detail.get_global_rect().end.y < 648, "312px detail slot reserves 24px per side for the frame and shadow around 264px content"):
			return
		var metadata := shell.find_child("RunMetadata", true, false) as Label
		var header := board.get_node("MapMetadata") as Label
		var night := board.get_node_or_null("MapNight") as Label
		if not _expect(metadata.get_line_count() == 2 and header.text == "ACT %d · %s" % [act, String(SCENE.ROOM_NAMES[act]).to_upper()] and night != null and night.text == "NIGHT %d" % session.run_seed and board.get_node_or_null("MapSeed") == null and (header.text + night.text).count(str(session.run_seed)) == 1, "painted header leads with act and room and shows the night identifier once, with no residual seed label"):
			return
		if not _expect(night.get_theme_font_size("font_size") < header.get_theme_font_size("font_size") and night.get_theme_color("font_color").a < header.get_theme_color("font_color").a and night.position.x >= header.position.x + header.size.x and night.get_rect().end.y <= header.get_rect().end.y + 1.0, "the night number sits after the act and room, smaller and quieter"):
			return
		var lamp := (table.get_node("Lamplight") as ColorRect).material as ShaderMaterial
		var focus: PackedVector2Array = table.call("focus_points")
		var available: Array = session.available_nodes()
		var current_marker := board.call("marker", session.current_node_id) as Button
		if not _expect(int(lamp.get_shader_parameter("focus_count")) == focus.size() and focus.size() == 1 + available.size() and focus[0].is_equal_approx(current_marker.position + current_marker.size * 0.5), "the board's light gathers on the player's stop and each stop they can go to"):
			return
		var tiers: Dictionary = {}
		for id: String in session.current_map.nodes:
			for child: Dictionary in session.current_map.get_children(id):
				var tier: StringName = board.call("route_tier", id, String(child["id"]))
				tiers[tier] = true
				if id == session.current_node_id and board.call("is_reachable", String(child["id"])) and not _expect(tier == &"live", "every route the player can take now is in the brightest tier"):
					return
		var route_tiers: Dictionary = MAP_VIEW.ROUTE_TIERS
		# At the start the only move is the pending race, so routes onward from it lead.
		if not _expect(tiers.has(&"near") and tiers.has(&"far") and not tiers.has(&"live"), "with a race pending, routes on from the player's stop lead and the rest of the act recedes"):
			return
		for wider: Array in [[&"live", &"near"], [&"near", &"far"]]:
			if not _expect(float(route_tiers[wider[0]][1]) > float(route_tiers[wider[1]][1]) and float(route_tiers[wider[0]][0]) > float(route_tiers[wider[1]][0]), "nearer routes are wider as well as brighter, so tone is not the only cue"):
				return
		if not _expect(bool((shell.find_child("RunChalkboard", true, false) as Control).get("refined_cards")), "active detail opts into finer layered chalkboard and paper edges"):
			return
		var chip_icons: Dictionary = {}
		for id: String in session.current_map.nodes:
			var kind := String(session.current_map.get_node(id)["type"])
			var chip := (board.call("marker", id) as Button).get_node_or_null("StopChip") as Control
			if not _expect(chip != null and chip.get("kind") == kind and chip.call("icon") == RUN_UI.TYPES[kind]["icon"] and chip.get("car_look") == null and chip.find_children("*", "TextureRect", true, false).is_empty(), "every map stop is an abstract chip carrying its kind's map icon, never a car sprite"):
				return
			var leads: bool = id == session.current_node_id or bool(board.call("is_reachable", id))
			var chip_selected := bool(chip.get("selected")) or bool(chip.get("hovered"))
			if not chip_selected and not _expect(chip.call("rim_tier") == (&"reachable" if leads else &"distant"), "stops the player can go to wear the lead rim and the rest of the act sits back"):
				return
			chip_icons[chip.call("icon")] = true
		var rim_tiers: Dictionary = BOARD_TOKEN.RIM_TIERS
		if not _expect(float(rim_tiers[&"reachable"][0]) > float(rim_tiers[&"distant"][0]) and float(rim_tiers[&"reachable"][1]) > float(rim_tiers[&"distant"][1]), "reachable chip rims are brighter and thicker than distant ones, so tone is not the only cue"):
			return
		if not _expect(SCENE.FOCUS_CHOICE_REACH <= SCENE.FOCUS_PLAYER_REACH and SCENE.FOCUS_PLAYER_REACH < 0.1 and SCENE.FOCUS_PEAK < 0.9, "the focus light is small, soft pools rather than a wash over the map"):
			return
		var legend_icons: Dictionary = {}
		for icon: Node in shell.find_child("RunLegend", true, false).find_children("*", "TextureRect", true, false):
			legend_icons[(icon as TextureRect).texture] = true
		if not _expect(legend_icons.size() == chip_icons.size() and legend_icons.keys().all(func(texture: Texture2D) -> bool: return chip_icons.has(texture)), "legend icons are exactly the icons on the map's chips"):
			return
		var legacy_snapshot := session_snapshot.duplicate(true)
		legacy_snapshot.erase("node_opponents")
		var legacy := RunSession.deserialize(legacy_snapshot)
		var legacy_look := BOARD_IDENTITY.look(legacy, legacy.current_node_id)
		if not _expect(legacy_look["key"] == legacy.opponents_for_node(legacy.current_node_id)["opponents"][0]["vehicle_id"], "older saves use domain-backfilled assignments when available"):
			return
		var circuit_fact := shell.find_child("CircuitFact", true, false) as VBoxContainer
		var circuit_value := circuit_fact.get_child(1) as Label
		var circuit_key := circuit_fact.get_child(0) as Label
		if not _expect(circuit_value.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and circuit_value.get_global_rect().position.y >= circuit_key.get_global_rect().end.y, "CIRCUIT value wraps below its label rather than sharing the narrow facts row"):
			return
		var go_button := shell.find_child("RunGo", true, false) as Control
		var inset_left := go_button.get_global_rect().position.x - (active_detail.get_global_rect().position.x - 8)
		var inset_right := active_detail.get_global_rect().end.x + 8 - go_button.get_global_rect().end.x
		if not _expect(inset_left >= 8 and is_equal_approx(inset_left, inset_right) and active_detail.get_global_rect().end.x + 22 <= slot.get_global_rect().end.x, "GO has matching frame insets and the complete right frame/shadow fits its slot"):
			return
		var active_legend := shell.find_child("RunLegend", true, false) as Control
		if not _expect(active_legend.get_global_rect().position.y >= 668 and active_legend.get_global_rect().end.y <= 720, "legend occupies the bottom strip below the enlarged map and instructions"):
			return
		var token := board.get_node("CarToken") as TextureRect
		if not _expect(token.size == Vector2(36, 36), "player car token grows with the 1.2x marker presentation"):
			return
		if not _expect(token.texture == IDENTITIES.car_texture(session.current_car_id), "the parked player car uses the identity library"):
			return
		var marker: Button = board.call("marker", session.current_node_id)
		var detail := shell.find_child("RunDetail", true, false) as Control
		var inset := detail.get_node("ChalkboardInset") as MarginContainer
		for edge: String in ["left", "right", "top", "bottom"]:
			if not _expect(inset.get_theme_constant("margin_" + edge) == SCENE.CHALK_PADDING, "chalkboard content has consistent inner padding"):
				return
		var toy := marker.get_node_or_null("StopChip") as Control
		if not _expect(marker.custom_minimum_size.is_equal_approx(Vector2(45.6, 45.6)) and toy.scale.is_equal_approx(Vector2.ONE * 1.2), "hit targets and physical chip artwork grow by twenty percent"):
			return
		if not _expect(toy != null and toy.mouse_filter == Control.MOUSE_FILTER_IGNORE, "physical chips leave input on the existing marker"):
			return
		if not _expect(board.call("selected_id") == session.current_node_id and bool(toy.get("selected")), "opening preview retains its selected ring and physical chip highlight"):
			return
		toy.set("reduced_motion", true)
		toy.call("set_selected", true)
		if not _expect(is_zero_approx(float(toy.get("lift"))), "reduced motion selects without chip lift"):
			return
		toy.set("reduced_motion", false)
		toy.call("set_selected", true)
		await create_timer(0.4).timeout
		if not _expect(float(toy.get("lift")) > 2.9 and table.modulate.a > 0.99, "arrival fades in and selection lifts the chip"):
			return
		for id: String in session.current_map.nodes:
			var kind := String(session.current_map.get_node(id)["type"])
			board.call("select", id)
			await process_frame
			var stop_car := shell.find_child("RunStop", true, false).find_child("StopCar", true, false) as Control
			if kind not in RunSession.RACE_NODE_TYPES:
				if not _expect(stop_car == null, "only race, rival and act-rival stops show a car in the detail slip"):
					return
				continue
			var roster: Dictionary = app.call("run_stop_opponents", id)
			var leader: Dictionary = roster["opponents"][0]
			if not _expect(stop_car != null and stop_car.get_meta("vehicle_id") == leader["vehicle_id"] and stop_car.get_meta("source") == "opponent" and stop_car.call("texture") == MATERIALS.hero_texture(String(leader["vehicle_id"])), "the detail slip shows the stop's assigned field leader or rival car"):
				return
			if not _expect((stop_car.call("texture") as Texture2D).get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE and is_equal_approx(detail.size.x, 264), "the slip car uses hero-scale rasterization without widening the 264px slip"):
				return
			var restored := RunSession.deserialize(session_snapshot)
			restored.current_map.act = act
			var again := BOARD_IDENTITY.look(restored, id)
			if not _expect(again["key"] == leader["vehicle_id"] and again["opponent_id"] == leader["id"], "node opponent appearance survives save reload"):
				return
			var empty := EmptyAssignments.new()
			empty.current_map = session.current_map
			empty.current_car_id = session.current_car_id
			var fallback_card := STOP_CAR.new(BOARD_IDENTITY.look(empty, id))
			if not _expect(fallback_card.get_meta("source") == "player" and fallback_card.get_meta("vehicle_id") == session.current_car_id and fallback_card.call("texture") == MATERIALS.hero_texture(session.current_car_id), "empty assignments fall back to the player's car in the detail slip"):
				return
			fallback_card.free()
		board.call("preview", session.current_node_id)
		if not _expect(shell.find_children("RunTabletop", "Control", true, false).size() == 1, "reopening replaces rather than stacks scenery"):
			return
		var checked_kinds: Array[String] = []
		for id: String in session.current_map.nodes:
			var kind := String(session.current_map.get_node(id)["type"])
			if checked_kinds.has(kind):
				continue
			checked_kinds.append(kind)
			board.call("select", id)
			await process_frame
			await process_frame
			var go := shell.find_child("RunGo", true, false) as Control
			if not _expect(detail.get_global_rect().end.y < active_legend.get_global_rect().position.y and detail.get_global_rect().encloses(go.get_global_rect()) and is_equal_approx(detail.size.x, 264), "each stop kind retains readable facts and GO above the bottom legend within the 264px slip"):
				return
		shell.call("show_title")
		await process_frame
		if not _expect(shell.find_child("RunTabletop", true, false) == null, "tabletop scenery does not leak onto other screens"):
			return
	session.current_map.act = 1
	RUN_WALK.settle(app, session)
	if not session.pending_offer.is_empty():
		app.call("run_decline_offer")
	shell.call("show_run_board")
	await process_frame
	await process_frame
	var moved := shell.find_child("RunBoard", true, false) as Control
	var live_routes := 0
	for child: Dictionary in session.current_map.get_children(session.current_node_id):
		var child_id := String(child["id"])
		if bool(moved.call("is_reachable", child_id)):
			live_routes += 1
			if not _expect(moved.call("route_tier", session.current_node_id, child_id) == &"live", "after a race, every route to a stop the player can go to is in the brightest tier"):
				return
	var moved_focus: PackedVector2Array = shell.find_child("RunTabletop", true, false).call("focus_points")
	if not _expect(live_routes > 0 and moved_focus.size() == 1 + session.available_nodes().size(), "after a race the light gathers on the player and each next choice"):
		return
	if not _expect(bool(app.call("update_setting", "reduced_motion", true)), "reduced-motion setting is persisted for shell presentation"):
		return
	var victory: RunSession = app.call("start_run", 71717)
	for act in RunSession.FINAL_ACT:
		if not _expect(RUN_WALK.walk_to(app, victory, "act_rival"), "victory fixture reaches each act rival"):
			return
		RUN_WALK.settle(app, victory)
	shell.call("show_run_board")
	await process_frame
	await process_frame
	if not await _expect_ending(shell, &"night_won", "WinnerCar", SCENE.SUNRISE):
		return
	app.call("start_run", 72727)
	app.call("abandon_run")
	shell.call("show_run_board")
	await process_frame
	await process_frame
	if not await _expect_ending(shell, &"night_lost", "SolitaryCar", SCENE.MOONLIGHT):
		return
	var victory_light := SCENE.new()
	victory_light.scene_mode = &"night_won"
	victory_light.act = 3
	victory_light.size = Vector2(1280, 720)
	root.add_child(victory_light)
	if not _expect(victory_light.get_node("RoomDressing").get_child_count() == 0, "victory removes bright static debris rather than presenting it as confetti"):
		return
	var dust := victory_light.get_node("BeamDust")
	if not _expect(dust.get_child_count() == 3, "victory keeps only three sparse light motes"):
		return
	for child: Node in dust.get_children():
		var mote := child as TextureRect
		var mask := mote.material as ShaderMaterial
		var start: Vector2 = mote.get_meta("beam_start")
		var end: Vector2 = mote.get_meta("beam_end")
		if not _expect(mote.texture == MATERIALS.SHADOW_CIRCLE and mote.size.x <= 4 and (mote.modulate.a < 0.14 or is_equal_approx(mote.modulate.a, 0.14)) and bool(mask.get_shader_parameter("sunrise")), "victory uses tiny low-opacity painted motes with the sunlight mask (size=%s alpha=%s sunrise=%s)" % [mote.size, mote.modulate.a, mask.get_shader_parameter("sunrise")]):
			return
		if not _expect(MATERIALS.beam_strength(start / victory_light.size, true) > 0.7 and MATERIALS.beam_strength(end / victory_light.size, true) > 0.7, "mote drift stays inside a sun beam and is masked away from dark zones"):
			return
	root.remove_child(victory_light)
	victory_light.queue_free()
	print("RUN_BOARD_SCENE_TEST PASS rooms=3 endings=2 route=hidden shadow=single reduced_motion=fade_only")
	quit(0)


func _test_intro(app: Node, shell: CanvasLayer) -> bool:
	if not _expect(not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)), "fresh profile begins with an unseen run intro"):
		return false
	shell.call("_on_art_action", &"new_run")
	for frame in 4:
		await process_frame
	await create_timer(0.2).timeout
	var note := shell.find_child("RunIntro", true, false) as Control
	var session: RunSession = app.call("current_run_session")
	var board := shell.find_child("RunBoard", true, false) as Control
	if not _expect(note != null and note.is_visible_in_tree() and note.mouse_filter == Control.MOUSE_FILTER_IGNORE and note.focus_mode == Control.FOCUS_NONE and root.gui_get_focus_owner() == board.call("marker", session.current_node_id), "first NEW RUN shows a nonblocking note without stealing initial marker focus"):
		return false
	var copy := note.get_node("RunIntroCopy") as Label
	if not _expect(copy.text == INTRO.COPY and copy.get_line_count() <= 3 and note.position.y == INTRO.NOTE_RECT.position.y and note.size == INTRO.NOTE_RECT.size and Rect2(Vector2.ZERO, note.size).grow(-8).encloses(copy.get_rect()) and not note.get_global_rect().intersects((board.call("marker", session.current_node_id) as Control).get_global_rect()), "intro is three literal lines on a contained slip clear of the opening marker"):
		return false
	(board.call("marker", session.current_node_id) as Button).pressed.emit()
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null and shell.get("_screen") == "run_board" and not bool(shell.get("_run_going")), "first press dismisses intro and only picks the preview, without travel"):
		return false
	var store: SaveStore = app.get("_save_store")
	var loaded := SAVE_STORE.new(store.save_path).load_data()
	if not _expect(not bool(loaded.get("run_intro_seen", true)), "dismissing the board note leaves driving controls unseen on disk"):
		return false
	app.set("_save_data", loaded)
	app.set("_current_run_session", RunSession.deserialize(loaded["current_run"]))
	shell.call("show_run_board")
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null, "save/load never reopens the dismissed note"):
		return false
	session = app.call("current_run_session")
	shell.call("_go_to_run_stop", session.current_node_id, false)
	await process_frame
	var ready := shell.find_child("DrivingReady", true, false) as Button
	if not _expect(ready != null, "unseen driving controls appear when the opening race is confirmed"):
		return false
	ready.pressed.emit()
	await create_timer(MAP_VIEW.TRAVEL_TIME + 0.3).timeout
	loaded = SAVE_STORE.new(store.save_path).load_data()
	if not _expect(bool(loaded.get("run_intro_seen", false)), "READY writes the intro flag to the profile save"):
		return false
	app.call("report_race_result", 1, 1.0, [], false, {})
	if not _expect(bool(app.call("confirm_new_championship")) and bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", false)), "championship reset preserves the additive intro flag"):
		return false
	shell.call("_on_art_action", &"new_run")
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null, "subsequent NEW RUN never repeats the note"):
		return false
	var fresh := (app.call("get_save_data") as Dictionary).duplicate(true)
	fresh["run_intro_seen"] = false
	app.set("_save_data", fresh)
	app.call("update_setting", "reduced_motion", true)
	shell.call("_on_art_action", &"new_run")
	for frame in 4:
		await process_frame
	note = shell.find_child("RunIntro", true, false) as Control
	if not _expect(note != null and note.modulate == Color.WHITE and note.position == note.get("anchor_position"), "reduced-motion intro is static"):
		return false
	board = shell.find_child("RunBoard", true, false) as Control
	session = app.call("current_run_session")
	for id: String in session.current_map.nodes:
		if id != session.current_node_id:
			(board.call("marker", id) as Button).grab_focus()
			break
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null and not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)), "focus travel dismisses the static board note without marking driving controls seen"):
		return false
	fresh = (app.call("get_save_data") as Dictionary).duplicate(true)
	fresh["run_intro_seen"] = false
	app.set("_save_data", fresh)
	shell.call("_on_art_action", &"new_run")
	for frame in 4:
		await process_frame
	board = shell.find_child("RunBoard", true, false) as Control
	var preview := String(board.call("selected_id"))
	if not _expect(shell.find_child("RunIntro", true, false) != null, "input fixture begins with an intro note"):
		return false
	for down: bool in [true, false]:
		var move := InputEventAction.new()
		move.action = &"ui_up"
		move.pressed = down
		Input.parse_input_event(move)
		await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null and board.call("selected_id") != preview and not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)), "first directional input dismisses without consuming focus movement or marking controls seen"):
		return false
	fresh = (app.call("get_save_data") as Dictionary).duplicate(true)
	fresh["run_intro_seen"] = false
	app.set("_save_data", fresh)
	shell.call("_on_art_action", &"your_run")
	await process_frame
	return _expect(shell.find_child("RunIntro", true, false) == null and not bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)), "resuming skips the board note but preserves unseen driving controls")


func _expect_ending(shell: CanvasLayer, mode: StringName, hero_name: String, tint: Color) -> bool:
	var table := shell.find_child("RunTabletop", true, false) as Control
	var board := shell.find_child("RunBoard", true, false) as Control
	if not _expect(table.get("scene_mode") == mode and table.get("lighting_tint") == tint, "ending selects its sunrise or moonlit palette"):
		return false
	if not _expect(not bool(board.get("route_visuals_visible")) and board.is_visible_in_tree(), "terminal retains its map node and layout but disables route drawing"):
		return false
	for visual: Node in board.get_children():
		if visual is CanvasItem and not _expect(not (visual as CanvasItem).is_visible_in_tree(), "terminal hides every marker, token and act header"):
			return false
	var legend := shell.find_child("RunLegend", true, false) as Control
	if not _expect(legend != null and not legend.is_visible_in_tree(), "terminal legend is hidden, not faded"):
		return false
	var hero := table.get_node_or_null(hero_name) as TextureRect
	if not _expect(hero != null and hero.size.y >= 220, "ending retains its large hero car"):
		return false
	if not _expect(MATERIALS.HERO_PIXEL_SCALE > 2 and hero.texture.get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE, "terminal hero uses the high-resolution native renderer"):
		return false
	var shadow := table.get_node_or_null("HeroShadow") as TextureRect
	if not _expect(shadow != null and shadow.texture == MATERIALS.SHADOW_CIRCLE and shadow.get_child_count() == 0 and shadow.draw.get_connections().is_empty(), "hero shadow is one painted soft texture, without stacked custom primitives"):
		return false
	if not _expect(shadow.modulate.r < 0.1 and shadow.modulate.a > 0.3, "white-alpha shadow artwork is tinted dark at runtime"):
		return false
	if not _expect(table.get_node("BeamDust").get_child_count() == 0 and table.get("_lamp_pulse") == null, "reduced motion disables all motes and lamp pulses"):
		return false
	var lamp := (table.get_node("Lamplight") as ColorRect).material as ShaderMaterial
	if not _expect([null, 0].has(lamp.get_shader_parameter("focus_count")), "endings keep their own light, without the board's focus pool"):
		return false
	var resting_position := hero.position
	await create_timer(0.4).timeout
	return _expect(hero.position == resting_position and table.modulate.a > 0.99 and bool(table.get("reduced_motion")), "reduced-motion ending crossfades without moving its hero")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_BOARD_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
