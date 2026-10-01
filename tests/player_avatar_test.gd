extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SHELL := preload("res://scripts/ui/app_shell.gd")

const CANDIDATE_SEED := 424242


class TestShell extends CanvasLayer:
	var last_screen := ""

	func show_title() -> void:
		last_screen = "title"

	func show_map(_summary: Dictionary = {}) -> void:
		last_screen = "map"

	func show_settings() -> void:
		last_screen = "settings"

	func show_save_error(_title: String, _detail: String, _retry_action: Callable, _back_action: Callable) -> void:
		last_screen = "save_error"

class RecordingSaveStore extends SaveStore:
	var save_count := 0

	func _init() -> void:
		super("user://tests/pocket_circuit_player_avatar_test.json")

	func save_data(data: Dictionary) -> bool:
		save_count += 1
		return true


func _initialize() -> void:
	call_deferred("_run_test")


func _hash(texture: Texture2D) -> String:
	if texture == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(texture.get_image().save_png_to_buffer())
	return context.finish().hex_encode()


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var player_id := CATALOG.player_driver_id()
	if not _expect(not player_id.is_empty(), "the catalog should declare exactly one player driver"):
		return
	var cast_seed := int(CATALOG.get_driver(player_id).get("avatar_art", {}).get("seed", -1))
	if not _expect(cast_seed == SAVE_STORE_SCRIPT.PLAYER_AVATAR_DEFAULT_SEED, "the save default must match the shipped player seed so an untouched save is unchanged"):
		return

	var store := RecordingSaveStore.new()
	app.set("_save_store", store)
	var shell := TestShell.new()
	app.set("_shell", shell)
	root.add_child(shell)
	var save_data := store.default_data()
	app.set("_save_data", save_data)
	if not _expect(int(save_data["player_avatar_seed"]) == cast_seed, "a fresh save should carry the shipped player portrait seed"):
		return

	var original := IDENTITIES.avatar_texture(player_id)
	if not _expect(original != null and original.get_size() == Vector2(128.0, 128.0), "the untouched player portrait should render natively at 128x128"):
		return
	var original_hash := _hash(original)

	# Preview changes the rendered portrait without writing the save.
	app.call("preview_player_avatar", CANDIDATE_SEED)
	var preview := IDENTITIES.avatar_texture(player_id)
	if not _expect(preview != null and _hash(preview) != original_hash, "previewing a seed must change the rendered portrait"):
		return
	if not _expect(int(app.call("get_save_data")["player_avatar_seed"]) == cast_seed and store.save_count == 0, "previewing must not write the save"):
		return
	if not _expect(IDENTITIES.avatar_payload(player_id).get("facing", "") == String(CATALOG.get_driver(player_id)["avatar_art"]["options"]["facing"]), "a random preview must keep the portrait facing direction stable"):
		return

	# Reloading the app re-installs the saved seed, discarding an unkept preview.
	app.call("_install_player_avatar")
	if not _expect(_hash(IDENTITIES.avatar_texture(player_id)) == original_hash, "an unkept preview must not survive a reload"):
		return

	app.call("preview_player_avatar", 7)
	app.call("save_player_avatar", CANDIDATE_SEED)
	if not _expect(store.save_count == 1 and int(app.call("get_save_data")["player_avatar_seed"]) == CANDIDATE_SEED, "keeping a look must persist exactly the candidate seed once"):
		return
	var kept := IDENTITIES.avatar_texture(player_id)
	var kept_hash := _hash(kept)
	if not _expect(kept != null and kept_hash != original_hash, "the kept portrait should replace the shipped look"):
		return
	app.call("_install_player_avatar")
	if not _expect(_hash(IDENTITIES.avatar_texture(player_id)) == kept_hash, "the kept portrait must survive a reload"):
		return
	if not _expect(int(JSON.parse_string(JSON.stringify(app.call("get_save_data")))["player_avatar_seed"]) == CANDIDATE_SEED, "the chosen seed must survive a save round-trip"):
		return

	# Keeping the same look again is a no-op, never an extra write.
	app.call("save_player_avatar", CANDIDATE_SEED)
	if not _expect(store.save_count == 1, "re-keeping the current look should not write the save again"):
		return

	# A new championship preserves the chosen portrait and resets everything else.
	app.call("confirm_new_championship")
	if not _expect(int(app.call("get_save_data")["player_avatar_seed"]) == CANDIDATE_SEED, "a new championship must keep the driver portrait"):
		return
	if not _expect(_hash(IDENTITIES.avatar_texture(player_id)) == kept_hash, "the portrait must stay installed after a new championship"):
		return

	# Out-of-range or malformed seeds fall back to the shipped seed, matching the
	# save store's existing bounded-int convention rather than clamping.
	var round_trip := SaveStore.new("user://tests/pocket_circuit_player_avatar_normalize.json")
	round_trip.remove_save()
	var candidates := [
		{"value": -5, "expected": cast_seed},
		{"value": 4.9, "expected": 4},
		{"value": SAVE_STORE_SCRIPT.PLAYER_AVATAR_MAX_SEED + 500, "expected": cast_seed},
		{"value": "pencil", "expected": cast_seed},
		{"value": null, "expected": cast_seed},
	]
	for candidate: Dictionary in candidates:
		var raw := store.default_data()
		raw["player_avatar_seed"] = candidate["value"]
		if not _expect(round_trip.save_data(raw), "the normalization fixture should persist"):
			return
		var loaded := round_trip.load_data()
		if not _expect(int(loaded["player_avatar_seed"]) == int(candidate["expected"]), "seed %s should normalize to %d but became %s" % [candidate["value"], candidate["expected"], loaded["player_avatar_seed"]]):
			return
	round_trip.remove_save()

	# Randomized seeds are bounded and varied.
	var seen: Dictionary = {}
	for i in 40:
		var seed := int(app.call("random_player_avatar_seed"))
		if not _expect(seed >= 0 and seed <= SAVE_STORE_SCRIPT.PLAYER_AVATAR_MAX_SEED, "a randomized seed must stay in range"):
			return
		seen[seed] = true
	if not _expect(seen.size() > 30, "randomized seeds should be varied, not repeating"):
		return

	for index in IDENTITIES.MAX_AVATAR_ENTRIES + 2:
		app.call("preview_player_avatar", CANDIDATE_SEED + index)
		var texture := IDENTITIES.avatar_texture(player_id)
		var payload := IDENTITIES.avatar_payload(player_id)
		if not _expect(texture != null and not payload.is_empty() and IDENTITIES.avatar_texture(player_id) == texture, "reading a shuffled portrait payload must keep its current texture cached"):
			return
		if not _expect(IDENTITIES._avatar_entry_order.count(player_id) == 1 and IDENTITIES._avatar_entry_order.size() <= IDENTITIES.MAX_AVATAR_ENTRIES, "shuffling one portrait must not create duplicate cache entries or evade the bound"):
			return
	app.call("_install_player_avatar")
	var ui := SHELL.new()
	root.add_child(ui)
	ui.configure(app)
	app.set("_shell", ui)
	var writes_before_preview := store.save_count
	for back_path in ["button", "cancel"]:
		ui.show_driver()
		ui.set("_preview_avatar_seed", CANDIDATE_SEED + 1)
		ui.call("_render_driver")
		if not _expect(_hash(IDENTITIES.avatar_texture(player_id)) != kept_hash, "the UI should render the unkept preview before leaving"):
			return
		if back_path == "button":
			var back_button: Button
			for node: Node in (ui.get("_content") as Control).get_children():
				if node is Button and node.text == "BACK":
					back_button = node
			if not _expect(back_button != null, "the driver screen should provide a Back button"):
				return
			back_button.pressed.emit()
		else:
			ui.go_back()
		if not _expect(_hash(IDENTITIES.avatar_texture(player_id)) == kept_hash and String(ui.get("_screen")) == "title", "%s Back must restore the saved look before showing the return screen" % back_path):
			return
	if not _expect(store.save_count == writes_before_preview and int(app.call("get_player_avatar_seed")) == CANDIDATE_SEED, "discarding previews must never write or change the saved seed"):
		return
	app.set("_shell", shell)
	ui.queue_free()
	shell.queue_free()
	await process_frame
	print("PLAYER_AVATAR_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PLAYER_AVATAR_TEST FAIL: " + message)
	quit(1)
	return false
