extends SceneTree

const MENU := preload("res://scripts/ui/championship_menu.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const COLLECTION_SIZE := 45
const VISIBLE_CARDS := 15


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	root.size = Vector2i(1280, 720)
	var entries: Array = []
	var ids: Array[String] = []
	for index in COLLECTION_SIZE:
		var car := {"id": "lazy_%d" % index, "seed": 904500 + index, "type": "compact", "roll": {}}
		entries.append(CATALOG.generated_vehicle(car))
		ids.append(car["id"])
	VehicleDirectory.install(entries)
	var menu := MENU.new()
	menu.reduced_motion = true
	root.add_child(menu)
	menu.show_garage(ids[-1], ids, "PERF", "PLAY", ids)
	var buttons: Dictionary = menu.get("_vehicle_buttons")
	var placeholder := IDENTITIES.car_icon_placeholder()
	if not _expect(IDENTITIES._car_texture_cache.size() == VISIBLE_CARDS + 1, "only initial visible rows and the selected hero rasterize synchronously"):
		return
	for index in COLLECTION_SIZE:
		var button := buttons[ids[index]] as Button
		var real := index < VISIBLE_CARDS or index == COLLECTION_SIZE - 1
		if not _expect((button.icon != placeholder) == real and IDENTITIES._car_texture_cache.has(ids[index]) == real, "cold icon coverage at card %d" % index):
			return
	if not _expect(menu.get("_stage").vehicle_id == ids[-1] and (buttons[ids[-1]] as Button).icon == IDENTITIES.car_texture(ids[-1]), "offscreen initial selection has its real stage identity immediately"):
		return
	for frame in 3:
		await process_frame
	if not _expect(_visible_icons_are_real(menu, placeholder), "focus-follow fills every newly visible row"):
		return
	var target := buttons[ids[20]] as Button
	if not _expect(target.icon == placeholder, "an unvisited middle row retains its lightweight placeholder"):
		return
	target.grab_focus()
	if not _expect(target.icon != placeholder and menu.get("_stage").vehicle_id == ids[20], "focus resolves the card and hero synchronously, before a frame elapses"):
		return
	await process_frame
	if not _expect(_visible_icons_are_real(menu, placeholder), "focus reveal fills its viewport within one frame"):
		return
	# Scroll without moving focus: identities follow the viewport, not selection.
	(menu.find_child("GaragePrimaryAction", true, false) as Button).grab_focus()
	var scroll := menu.find_child("GridScroll", true, false) as ScrollContainer
	if not _expect((buttons[ids[15]] as Button).icon == placeholder, "scroll fixture still has an unvisited row"):
		return
	for offset in [0, 336, 672, 1008]:
		scroll.scroll_vertical = offset
		await process_frame
		if not _expect(_visible_icons_are_real(menu, placeholder), "scroll fills visible rows at %d" % offset):
			return
		if offset == 336 and not _expect((buttons[ids[15]] as Button).icon != placeholder and menu.selected_vehicle_id == ids[20], "scrolling resolves an unvisited row without changing the selected hero"):
			return
	for id in ids:
		if not _expect((buttons[id] as Button).icon != placeholder, "scrolling the collection eventually resolves every card"):
			return
	var first_texture := (buttons[ids[0]] as Button).icon
	menu.show_garage(ids[0], ids, "PERF", "PLAY", ids)
	buttons = menu.get("_vehicle_buttons")
	if not _expect((buttons[ids[0]] as Button).icon == first_texture, "reopening reuses the existing identity cache"):
		return
	# Existing oldest-out policy must not turn into recency-on-hit eviction.
	var oldest := String(IDENTITIES._car_entry_order[0])
	IDENTITIES.car_texture(oldest)
	for index in IDENTITIES.MAX_CAR_ENTRIES:
		IDENTITIES._note_car_entry("lazy_eviction_%d" % index)
	if not _expect(IDENTITIES._car_entry_order.size() == IDENTITIES.MAX_CAR_ENTRIES and not IDENTITIES._car_texture_cache.has(oldest) and IDENTITIES._car_texture_cache.is_empty(), "oldest-out eviction remains bounded and cache hits do not promote entries"):
		return
	menu.clear()
	await process_frame
	menu.free()
	VehicleDirectory.clear()
	print("GARAGE_LAZY_ICON_TEST PASS visible=15 selected_immediate focus_immediate scroll_fill cache_bounded_oldest_out")
	quit(0)


func _visible_icons_are_real(menu: Control, placeholder: Texture2D) -> bool:
	var count := 0
	for button: Button in (menu.get("_vehicle_buttons") as Dictionary).values():
		if button.modulate.a > 0.0:
			count += 1
			if button.icon == null or button.icon == placeholder:
				return false
	return count > 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("GARAGE_LAZY_ICON_TEST FAIL: " + message)
		quit(1)
	return condition
