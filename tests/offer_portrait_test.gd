extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
const DIRECTORY := preload("res://scripts/progression/driver_directory.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
var _failed := false


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
	var session := SESSION.create(33333)
	for node: Dictionary in session.current_map.nodes.values():
		if node["type"] == "rival":
			session.current_node_id = node["id"]
			session.run_state.row = node["row"]
			session.resolve_rival(session.current_node_id, true)
			break
	_expect(not session.pending_offer_driver.is_empty(), "fixture has a defeated driver")
	app.set("_current_run_session", session)
	app.set("current_race_session", {})
	app.call("persist_current_run")
	session.pending_offer_driver.erase("avatar_art")
	DIRECTORY.install_opponents([session.pending_offer_driver])
	var driver_id := String(session.pending_offer_driver.get("id", ""))
	_expect(not driver_id.is_empty() and CATALOG.get_driver(driver_id).get("avatar_art", {}).is_empty(), "generated opponent has no configured avatar")
	shell.call("show_run_offer")
	await process_frame
	var portrait := shell.find_child("OfferPortrait", true, false) as TextureRect
	_expect(portrait != null and portrait.texture != null and portrait.is_visible_in_tree(), "offer displays a generated face")
	if portrait != null and portrait.texture != null:
		_expect(not portrait.texture.get_image().is_invisible(), "portrait contains visible pixels")
	var payload := IDENTITIES.avatar_payload(driver_id)
	_expect(not payload.is_empty(), "fallback uses the procedural avatar payload")
	for index in IDENTITIES.MAX_AVATAR_ENTRIES + 1:
		_expect(IDENTITIES.avatar_texture("op-portrait-eviction-%d" % index) != null, "every unknown opponent gets a face")
	DIRECTORY.clear()
	_expect(IDENTITIES.avatar_payload(driver_id) == payload, "face is stable after roster removal and cache eviction")
	_expect(IDENTITIES.avatar_payload("op-portrait-other") != payload, "distinct opponent ids vary their faces")
	var cast := CATALOG.get_driver("rae")
	var art: Dictionary = cast["avatar_art"]
	_expect(IDENTITIES.avatar_payload("rae") == preload("res://scripts/vendor/procedural_2d/procedural_avatar_generator.gd").generate(int(art["seed"]), art.get("options", {})), "configured cast portrait is unchanged")
	if _failed:
		quit(1)
		return
	print("OFFER_PORTRAIT_TEST PASS fallback=visible deterministic=eviction_safe cast=unchanged")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("OFFER_PORTRAIT_TEST FAIL: " + message)
