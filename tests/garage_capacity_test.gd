extends SceneTree

const MENU := preload("res://scripts/ui/championship_menu.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const COLLECTION_SIZE := 45
var _actions: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	root.size = Vector2i(1280, 720)
	var records: Array = []
	var ids: Array[String] = []
	for index in COLLECTION_SIZE:
		var record := CATALOG.get_vehicle("rustbug")
		var id := "capacity_%02d" % index
		record["id"] = id
		record["name"] = "CAR %02d" % index
		record["car_art"]["seed"] = 242600 + index
		record["won_from"] = "rival" if index % 2 == 0 else "steam"
		records.append(record)
		ids.append(id)
	VehicleDirectory.install(records)
	var menu := MENU.new()
	menu.reduced_motion = true
	root.add_child(menu)
	menu.action_requested.connect(func(action: StringName): _actions.append(action))
	menu.show_garage(ids[0], ids, "QUICK RACE · YOUR MACHINE", "NEXT: TRACK", ids, "THE GARAGE")
	for frame in 4:
		await process_frame
	var scroll := menu.find_child("GridScroll", true, false) as ScrollContainer
	var counter := menu.find_child("GarageCarCounter", true, false) as Label
	var buttons: Dictionary = menu.get("_vehicle_buttons")
	if not _expect(buttons.size() == COLLECTION_SIZE and counter.text == "45 CARS", "counter and cards include the entire collection"):
		return
	var continuation := menu.find_child("GridContinuation", true, false) as TextureRect
	var paging_hint := menu.find_child("GaragePagingHint", true, false) as Label
	if not _expect(continuation.visible and continuation.texture is GradientTexture2D and continuation.get_rect().end.y <= scroll.get_rect().end.y and paging_hint.position.y >= scroll.get_rect().end.y, "overflow uses a gradient continuation strip; paging stays outside the viewport"):
		return
	if not _expect((buttons[ids[14]] as Button).modulate.a == 1.0 and (buttons[ids[15]] as Button).modulate.a == 0.0, "three complete rows show; the cropped fourth row and its origin marks are masked"):
		return
	for index in ids.size():
		var button := buttons[ids[index]] as Button
		if not _expect(button.position == Vector2(8 + (index % 5) * 136, 38 + (index / 5) * 112) and button.size == Vector2(124, 100), "five-column geometry at card %d" % index):
			return
		button.grab_focus()
		for frame in 2:
			await process_frame
		if not _expect(menu.selected_vehicle_id == ids[index] and menu.get("_stage").vehicle_id == ids[index] and scroll.get_global_rect().encloses(button.get_global_rect()), "selection and focus-follow at card %d" % index):
			return
		if not _expect(button.modulate.a == 1.0 and _whole_rows(menu, scroll), "focus and every rendered row retain complete border clearance"):
			return
		if not _expect(menu.get("_vehicle_name").text == "CAR %02d" % index and menu.get("_archetype").text == "BALANCED" and menu.get("_stage").shape.keys() == CarProfile.AXES, "each selected car updates the name, archetype and six-axis identity"):
			return
		var origin := menu.find_child("GarageOrigin", true, false) as Label
		if not _expect(origin.visible == (index != 0) and (index % 2 == 0 or origin.text == "IN YOUR STEAM INVENTORY"), "won and Steam origins remain readable"):
			return
	var cached := IDENTITIES.car_texture(ids[0])
	for id in ids:
		if not _expect(IDENTITIES._car_texture_cache.has(id), "collection textures remain resident"):
			return
	if not _expect(IDENTITIES.car_texture(ids[0]) == cached and IDENTITIES.MAX_CAR_ENTRIES == 200, "cache holds a large collection without regeneration"):
		return
	if not _expect(not continuation.visible, "the continuation cue disappears at the collection end"):
		return
	scroll.scroll_vertical = 40
	for frame in 3:
		await process_frame
	if not _expect(scroll.scroll_vertical == 0 and _whole_rows(menu, scroll), "scrollbar movement settles to complete-row boundaries"):
		return
	(buttons[ids[0]] as Button).grab_focus()
	await _tap(&"ui_right")
	if not _expect(root.gui_get_focus_owner() == buttons[ids[1]], "Right moves one column"):
		return
	await _tap(&"ui_down")
	if not _expect(root.gui_get_focus_owner() == buttons[ids[6]], "Down preserves the column"):
		return
	await _tap(&"ui_page_down")
	if not _expect(root.gui_get_focus_owner() == buttons[ids[21]], "Page Down jumps three rows"):
		return
	var shoulder := InputEventJoypadButton.new()
	shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
	shoulder.pressed = true
	Input.parse_input_event(shoulder)
	await process_frame
	if not _expect(root.gui_get_focus_owner() == buttons[ids[6]], "LB jumps back three rows"):
		return
	(buttons[ids[-1]] as Button).grab_focus()
	await _tap(&"ui_down")
	var action := root.gui_get_focus_owner() as Button
	if not _expect(action.text == "NEXT: TRACK", "Down from the last row reaches PLAY"):
		return
	action.pressed.emit()
	await _tap(&"ui_left")
	await _tap(&"ui_left")
	action = root.gui_get_focus_owner() as Button
	if not _expect(action.text == "BACK", "footer always reaches BACK"):
		return
	action.pressed.emit()
	await _tap(&"ui_up")
	if not _expect(_actions == [&"play_vehicle", &"back"] and root.gui_get_focus_owner() == buttons[ids[-1]], "actions preserve semantics and Up restores selected car"):
		return
	# Separate headers need more vertical space than three rows of one type.
	var shipped := CATALOG.garage_order(CATALOG.quick_race_vehicle_ids())
	var eleven := shipped.duplicate()
	eleven.append_array(ids.slice(0, 3))
	for roster: Array[String] in [shipped, CATALOG.garage_order(eleven)]:
		menu.show_garage("rustbug", roster, "QUICK RACE", "NEXT: TRACK", roster)
		for frame in 4:
			await process_frame
		scroll = menu.find_child("GridScroll", true, false) as ScrollContainer
		buttons = menu.get("_vehicle_buttons")
		for id in ["anvil", "scrapjaw"]:
			if not _expect((buttons[id] as Button).modulate.a == 1.0 and _whole_rows(menu, scroll), "MUSCLE borders fit under the third section header with %d cars" % roster.size()):
				return
	# Exercise oldest-out eviction without generating hundreds of images.
	for index in IDENTITIES.MAX_CAR_ENTRIES + 1:
		IDENTITIES._note_car_entry("eviction_%d" % index)
	if not _expect(IDENTITIES._car_entry_order.size() == 200 and not IDENTITIES._car_entry_order.has("eviction_0") and not IDENTITIES._car_texture_cache.has(ids[0]), "oldest-out eviction keeps the cache bounded"):
		return
	menu.free()
	VehicleDirectory.clear()
	print("GARAGE_CAPACITY_TEST PASS cars=45 columns=5 page_rows=3 cache=200")
	quit(0)


func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _whole_rows(menu: Control, scroll: ScrollContainer) -> bool:
	var safe := scroll.get_global_rect()
	safe.size.y -= 32.0
	for button: Button in (menu.get("_vehicle_buttons") as Dictionary).values():
		if button.modulate.a > 0.0 and not safe.encloses(button.get_global_rect().grow(8.0)):
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("GARAGE_CAPACITY_TEST FAIL: " + message)
		quit(1)
	return condition
