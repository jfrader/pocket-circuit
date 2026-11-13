extends RefCounted

## Haul rules operate on RunSession's state; there is no second inventory.
const CATALOG := preload("res://data/championship/catalog.gd")
const STATE := preload("res://scripts/progression/run_state.gd")
const MAP := preload("res://scripts/progression/run_map.gd")
const RANSOM_POINTS := 10
const MAX_CONSUMABLES := 0x7FFFFFFF

static func spare_vehicle(sess, driver: Dictionary) -> String:
	var original: String = driver.get("vehicle_id", "")
	var band := _band(original)
	if band.is_empty():
		return ""
	# Rosters assign one car per driver, not personal spare inventories. The
	# honest available pool is distinct cars in this night's assigned rosters;
	# a same-tier chassis is a spare candidate, not proof of driver ownership.
	for nodes: Dictionary in sess.node_opponents.values():
		for roster: Dictionary in nodes.values():
			for opponent: Dictionary in roster["opponents"]:
				var candidate: String = opponent["vehicle_id"]
				if candidate != original and _band(candidate) == band:
					return candidate
	return ""

static func _band(vehicle_id: String) -> String:
	var vehicle := CATALOG.get_vehicle(vehicle_id)
	var car_type: String = vehicle.get("car_art", {}).get("type", "")
	return STATE.TYPE_TO_TIER.get(car_type, "")

static func hot_choice_reason(sess, vehicle_id: String) -> String:
	if sess.failed or sess.completed:
		return "night ended"
	if vehicle_id.is_empty() or vehicle_id != sess.pending_offer:
		return "not the pending offer"
	if sess.pending_chaser != null:
		return "chase already pending"
	if sess.pending_offer_driver.is_empty():
		return "no robbed driver"
	if spare_vehicle(sess, sess.pending_offer_driver).is_empty():
		return "no same-band spare in the run roster"
	return ""

static func choose_offer(sess, choice: String) -> bool:
	if sess.pending_offer.is_empty() or sess.failed or sess.completed:
		return false
	if choice not in ["hot", "ahead", "home"]:
		return false
	if choice == "hot" and not hot_choice_reason(sess, sess.pending_offer).is_empty():
		return false
	if choice == "ahead" and sess.run_points < sess.pending_offer_points:
		return false
	var vid: String = sess.pending_offer
	if choice != "home":
		sess.current_car_id = vid
		sess.boot_cars[vid] = sess.pending_offer_driver.duplicate(true)
	if choice == "ahead":
		sess.run_points -= sess.pending_offer_points
	if choice == "hot":
		var chaser: Dictionary = sess.pending_offer_driver.duplicate(true)
		chaser["chase_vehicle_id"] = spare_vehicle(sess, sess.pending_offer_driver)
		chaser["haul_vehicle_id"] = vid
		sess.pending_chaser = chaser
	clear_offer(sess)
	return true

static func clear_offer(sess) -> void:
	sess.pending_offer = ""
	sess.pending_offer_driver = {}
	sess.pending_offer_points = 0

static func bank(sess) -> Array[String]:
	var banked: Array[String] = []
	banked.assign(sess.boot_cars.keys())
	sess.boot_cars.clear()
	sess.pending_chaser = null
	return banked

static func impound(sess) -> Array[String]:
	var captured: Array[String] = []
	captured.assign(sess.boot_cars.keys())
	for vid: String in captured:
		if not sess.impounded_cars.has(vid):
			sess.impounded_cars.append(vid)
	sess.boot_cars.clear()
	sess.pending_chaser = null
	if captured.has(sess.current_car_id):
		for vid: String in sess.owned_cars:
			if not sess.impounded_cars.has(vid):
				sess.current_car_id = vid
				break
	return captured

static func ransom(sess, vehicle_id: String) -> bool:
	if sess.failed or sess.completed or not sess._is_current_node_type("parts_van"):
		return false
	if sess.resolved_nodes.has(sess.current_node_id) or not sess.impounded_cars.has(vehicle_id) or sess.run_points < RANSOM_POINTS:
		return false
	sess.run_points -= RANSOM_POINTS
	sess.impounded_cars.erase(vehicle_id)
	sess.resolved_nodes[sess.current_node_id] = true
	return true

static func add_consumable(sess, field: String, count: int) -> bool:
	var current: int = sess.get(field)
	if count <= 0 or count > MAX_CONSUMABLES - current or sess.failed or sess.completed:
		return false
	sess.set(field, current + count)
	return true

static func spend_consumable(sess, field: String) -> bool:
	var current: int = sess.get(field)
	if current <= 0 or sess.failed or sess.completed:
		return false
	sess.set(field, current - 1)
	return true

static func buy_consumable(sess, field: String, price: int) -> bool:
	if sess.van_offer_consumables().is_empty() or sess.run_points < price:
		return false
	if not add_consumable(sess, field, 1):
		return false
	sess.run_points -= price
	sess.resolved_nodes[sess.current_node_id] = true
	return true

static func serialize(sess) -> Dictionary:
	return {
		"boot_cars": sess.boot_cars.duplicate(true),
		"impounded_cars": sess.impounded_cars.duplicate(),
		"pending_chaser": sess.pending_chaser.duplicate(true) if sess.pending_chaser != null else null,
		"pending_offer_driver": sess.pending_offer_driver.duplicate(true),
		"pending_offer_points": sess.pending_offer_points,
		"tow_count": sess.tow_count,
		"nitro_count": sess.nitro_count,
		"towed_to_bench": sess.towed_to_bench,
	}

## Assign only after the entire new block passes. Missing fields are legacy cold state.
static func deserialize(sess, data: Dictionary) -> bool:
	var boot: Variant = data.get("boot_cars", {})
	var impounded: Variant = data.get("impounded_cars", [])
	var offer_driver: Variant = data.get("pending_offer_driver", {})
	var chaser: Variant = data.get("pending_chaser")
	if boot is not Dictionary or impounded is not Array or offer_driver is not Dictionary:
		return false
	if data.get("towed_to_bench", false) is not bool:
		return false
	for key: String in ["tow_count", "nitro_count"]:
		if not MAP.is_integer(data.get(key, 0), 0, MAX_CONSUMABLES):
			return false
	if not MAP.is_integer(data.get("pending_offer_points", 0), 0, sess.RUN_POINTS_BY_FINISH[1]):
		return false
	var clean_boot := {}
	for vid: Variant in boot:
		if not _is_won(sess, vid) or boot[vid] is not Dictionary:
			return false
		var driver := _normalized_driver(sess, boot[vid])
		if not boot[vid].is_empty() and driver.is_empty():
			return false
		clean_boot[vid] = driver
	var seen := {}
	for vid: Variant in impounded:
		if not _is_won(sess, vid) or boot.has(vid) or seen.has(vid) or vid == sess.pending_offer:
			return false
		seen[vid] = true
	var clean_offer := _normalized_driver(sess, offer_driver)
	if sess.pending_offer.is_empty():
		# A dropped offer (including the stored self-offer normalization in
		# RunSession.deserialize) drops its driver and payout metadata too.
		clean_offer = {}
		sess.pending_offer_driver = {}
		sess.pending_offer_points = 0
	else:
		sess.pending_offer_driver = clean_offer
		sess.pending_offer_points = int(data.get("pending_offer_points", 0))
		if not offer_driver.is_empty() and clean_offer.is_empty():
			return false
	if boot.has(sess.pending_offer):
		return false
	if chaser != null:
		if chaser is not Dictionary:
			return false
		var driver: Dictionary = chaser.duplicate(true)
		var haul_id: Variant = driver.get("haul_vehicle_id")
		var spare: Variant = driver.get("chase_vehicle_id")
		driver.erase("haul_vehicle_id")
		driver.erase("chase_vehicle_id")
		var clean_driver := _normalized_driver(sess, driver)
		if haul_id is not String or spare is not String or not clean_boot.has(haul_id) or clean_driver.is_empty() or clean_boot[haul_id] != clean_driver:
			return false
		if spare.is_empty() or spare != spare_vehicle(sess, clean_driver):
			return false
		chaser = clean_driver.duplicate(true)
		chaser["haul_vehicle_id"] = haul_id
		chaser["chase_vehicle_id"] = spare
	sess.boot_cars = clean_boot
	sess.impounded_cars.assign(impounded)
	sess.pending_chaser = chaser.duplicate(true) if chaser != null else null
	sess.tow_count = int(data.get("tow_count", 0))
	sess.nitro_count = int(data.get("nitro_count", 0))
	sess.towed_to_bench = data.get("towed_to_bench", false)
	return true

static func _is_won(sess, vid: Variant) -> bool:
	return vid is String and sess.owned_cars.has(vid) and not sess.won_car(vid).is_empty()

static func _normalized_driver(sess, driver: Dictionary) -> Dictionary:
	# Assignments were already normalized by DriverRoster, including identity,
	# art and AI style. Exact membership validates all fields without a twin parser.
	for nodes: Dictionary in sess.node_opponents.values():
		for roster: Dictionary in nodes.values():
			for known: Dictionary in roster["opponents"]:
				if driver.get("id") != known["id"] or driver.size() != known.size():
					continue
				var clean := driver.duplicate(true)
				var art: Variant = clean.get("avatar_art")
				if art is not Dictionary or not MAP.is_integer(art.get("seed"), 0, MAP.HASH_MASK):
					return {}
				art["seed"] = int(art["seed"])
				# JSON integral numbers become floats. Convert the only integral
				# identity field before comparing against the normalized roster.
				if clean == known:
					return known.duplicate(true)
	return {}
