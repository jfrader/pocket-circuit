extends SceneTree

const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const HUD_SCRIPT := preload("res://scripts/ui/race_hud.gd")
const SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")
const FIXTURE := preload("res://tests/app_shell_focus_test.gd")

var _captures := ""
var _activations := 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_captures = OS.get_environment("PC_UI_CAPTURE_DIR")
	var canvas := Control.new()
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wide := _button(canvas, Rect2(48, 60, 420, 64), "QUICK RACE")
	var narrow := _button(canvas, Rect2(520, 60, 180, 64), "OPTIONS")
	var primary := _button(canvas, Rect2(48, 160, 420, 64), "PLAY", true)
	var disabled_button := _button(canvas, Rect2(520, 160, 180, 64), "LOCKED")
	disabled_button.disabled = true
	wide.pressed.connect(func(): _activations += 1)
	await _frame()
	var normal: StyleBoxTexture = wide.get_theme_stylebox("normal")
	var hover: StyleBoxTexture = wide.get_theme_stylebox("hover")
	if not _expect(normal.get_texture_margin(SIDE_LEFT) > 0 and normal.get_texture_margin(SIDE_TOP) > 0, "panel borders must be nine-sliced rather than scaled as a full image"):
		return
	if not _expect(normal.modulate_color != hover.modulate_color and wide.get_theme_color("font_hover_color") != wide.get_theme_color("font_color"), "hover needs visible background and text contrast"):
		return
	var before: Image
	if DisplayServer.get_name() != "headless":
		before = root.get_texture().get_image()
		var first_corner := before.get_region(Rect2i(49, 61, 10, 10))
		var second_corner := before.get_region(Rect2i(521, 61, 10, 10))
		if not _expect(first_corner.get_data() == second_corner.get_data(), "wide and narrow buttons must render identical corner pixels"):
			return
	await _motion(wide.get_global_rect().get_center())
	await create_timer(0.16).timeout
	await _frame()
	if not _expect(float(wide.get("feedback")) > 0.95, "mouse hover should animate the accent to its active state"):
		return
	if before != null:
		var hovered := root.get_texture().get_image()
		if not _expect(before.get_region(Rect2i(48, 60, 420, 64)).get_data() != hovered.get_region(Rect2i(48, 60, 420, 64)).get_data(), "hover must visibly change rendered pixels"):
			return
	await _click(wide.get_global_rect().get_center(), true)
	if not _expect(wide.is_pressed(), "mouse-down should have a distinct pressed state"):
		return
	await _motion(Vector2(1100, 600))
	await _click(Vector2(1100, 600), false)
	if not _expect(_activations == 0, "dragging outside before release must cancel activation"):
		return
	narrow.grab_focus()
	await _motion(wide.get_global_rect().get_center())
	if not _expect(root.gui_get_focus_owner() == narrow, "mouse hover must not steal keyboard focus"):
		return
	await _click(wide.get_global_rect().get_center(), true)
	await _click(wide.get_global_rect().get_center(), false)
	if not _expect(_activations == 1, "a completed click should activate exactly once"):
		return
	wide.set("reduced_motion", true)
	await _motion(Vector2(1100, 600))
	await _motion(wide.get_global_rect().get_center())
	if not _expect(is_equal_approx(float(wide.get("feedback")), 1.0), "reduced motion should apply feedback immediately"):
		return
	await _motion(disabled_button.get_global_rect().get_center())
	await _click(disabled_button.get_global_rect().get_center(), true)
	await _click(disabled_button.get_global_rect().get_center(), false)
	if not _expect(not disabled_button.is_pressed() and is_zero_approx(float(disabled_button.get("feedback"))) and _activations == 1, "disabled buttons must remain inactive"):
		return
	primary.grab_focus()
	await _frame()
	await _capture("button-states.png")
	canvas.queue_free()
	await process_frame
	var hud := HUD_SCRIPT.new()
	root.add_child(hud)
	hud.set_telemetry(2, 4, 2, 3, 92.5, 0.64, 0.38)
	hud.set_route_progress(PackedFloat32Array([0.7, 0.65, 0.53, 0.47]), 1, 4)
	for height in [720, 800]:
		root.content_scale_size = Vector2i(1280, height)
		root.size = Vector2i(1280, height)
		await _frame()
		await _frame()
		if not _expect(root.get_visible_rect().size == Vector2(1280, height), "HUD test must use the requested logical viewport, not just resize the window"):
			return
		var layout := hud.get_layout_rects()
		var covered := 0.0
		for key: String in layout:
			var rect: Rect2 = layout[key]
			if not _expect(root.get_visible_rect().encloses(rect), "HUD %s must fit at %dp" % [key, height]):
				return
			covered += rect.get_area()
			for other: String in layout:
				if key != other and not _expect(not rect.intersects(layout[other]), "HUD instruments must not overlap"):
					return
		if not _expect(covered / root.get_visible_rect().get_area() < 0.12, "HUD including warning must leave at least 88% of the viewport unobscured"):
			return
		await _capture("hud-layout-%d.png" % height)
	hud.queue_free()
	await process_frame
	var app := FIXTURE.TestApp.new()
	var shell := SHELL_SCRIPT.new()
	root.add_child(app)
	root.add_child(shell)
	shell.configure(app)
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	shell.show_title()
	await _frame()
	await _frame()
	for node: Node in shell.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text == "QUICK RACE":
			await _motion(button.get_global_rect().get_center())
	await create_timer(0.16).timeout
	await _capture("title-hover.png")
	shell.show_vehicle_select("kitchen_crumb_rush")
	await _frame()
	await _frame()
	var rustbug := shell.find_child("Vehicle_rustbug", true, false) as Button
	await _motion(rustbug.get_global_rect().get_center())
	await create_timer(0.16).timeout
	if not _expect(String(shell.get("_current_vehicle_select_id")) == "pinbolt" and not bool(rustbug.get("selected")), "hover styling must remain distinct from the committed car selection"):
		return
	await _capture("garage-hover.png")
	shell.queue_free()
	app.queue_free()
	await process_frame
	if not _check_skin_cache_bounds():
		return
	print("MENU_FEEDBACK_TEST PASS borders_hover_press_focus_disabled_reduced_motion_hud_bounds")
	quit(0)


func _check_skin_cache_bounds() -> bool:
	SKIN._flat_cache.clear()
	SKIN._flat_order.clear()
	SKIN._svg_cache.clear()
	SKIN._svg_order.clear()
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='2' height='2'><rect width='2' height='2' fill='#ffffff'/></svg>"
	var first_flat: StyleBoxFlat = SKIN._flat(Color(0, 0, 0), Color.WHITE, 0, 1)
	var first_flat_key: String = SKIN._flat_order[0]
	var first_svg: Texture2D = SKIN._svg("cache_0", svg)
	for index in range(1, SKIN.MAX_SKIN_CACHE_ENTRIES + 1):
		SKIN._flat(Color.BLACK, Color.WHITE, index, 1)
		SKIN._svg("cache_%d" % index, svg)
	if not _expect(SKIN._flat_cache.size() == SKIN.MAX_SKIN_CACHE_ENTRIES and SKIN._svg_cache.size() == SKIN.MAX_SKIN_CACHE_ENTRIES, "skin caches must stay bounded"):
		return false
	if not _expect(not SKIN._flat_cache.has(first_flat_key) and not SKIN._svg_cache.has("cache_0"), "oldest cached skin entries must be evicted"):
		return false
	if not _expect(SKIN._flat(Color(0, 0, 0), Color.WHITE, 0, 1) != first_flat and SKIN._svg("cache_0", svg) != first_svg, "oldest cached skin entries must be evicted"):
		return false
	return true


func _button(parent: Node, rect: Rect2, text: String, primary: bool = false) -> Button:
	var button := BUTTON_SCRIPT.new() as Button
	button.position = rect.position
	button.size = rect.size
	button.text = text
	SKIN.apply_button(button, primary)
	parent.add_child(button)
	return button


func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)
	await _frame()


func _click(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await _frame()


func _frame() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _capture(filename: String) -> void:
	if _captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frame()
	var error := root.get_texture().get_image().save_png(_captures.path_join(filename))
	_expect(error == OK, "visual evidence must be written successfully")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MENU_FEEDBACK_TEST FAIL: " + message)
	quit(1)
	return false
