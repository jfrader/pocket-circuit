class_name ChampionshipCatalog
extends RefCounted

const POINTS_BY_FINISH := {1: 10, 2: 7, 3: 5, 4: 3}
const SECOND_EVENT_GATE := 10
const FINALE_GATE := 20

const CAST := [
	{
		"id": "rae",
		"name": "Rae Sparks",
		"role": "Player driver",
		"identity": "Adaptable newcomer; starts in the Rustbug",
		"vehicle_id": "rustbug",
		"avatar_art": {
			"seed": 91001,
			"options": {
				"gender": "female",
				"face_shape": "oval", "skin_tone": "golden", "hair_style": "curls",
				"hair_color": "blue_black", "brow_style": "arched", "eye_style": "wide",
				"eye_color": "hazel", "nose_style": "short", "mouth_style": "grin",
				"facial_hair": "none", "accessory": "headband", "marking": "freckles",
				"outfit": "jacket", "accent_palette": "marigold", "facing": "right",
			},
		},
	},
	{
		"id": "inez",
		"name": "Inez \"Spanner\" Solis",
		"role": "Mentor and garage owner",
		"identity": "Practical, warm, never stops tuning",
		"vehicle_id": "rustbug",
		"avatar_art": {
			"seed": 91002,
			"options": {
				"gender": "female",
				"face_shape": "square", "skin_tone": "amber", "hair_style": "top_knot",
				"hair_color": "espresso", "brow_style": "thick", "eye_style": "hooded",
				"eye_color": "coffee", "nose_style": "broad", "mouth_style": "smile",
				"facial_hair": "none", "accessory": "earring", "marking": "beauty_spot",
				"outfit": "collared", "accent_palette": "lagoon", "facing": "right",
			},
		},
	},
	{
		"id": "juniper",
		"name": "Juniper Gear",
		"role": "Act I rival",
		"identity": "Precise lines and late braking in the Pinbolt",
		"vehicle_id": "pinbolt",
		"ai_style": {
			"corner_pace": 1.04, "brake_timing": 0.9, "boost_eagerness": 1.0,
			"overtake_aggression": 1.0, "shortcut_preference": 1.0, "line_commitment": 1.06,
		},
		"avatar_art": {
			"seed": 91003,
			"options": {
				"gender": "female",
				"face_shape": "diamond", "skin_tone": "ivory", "hair_style": "side_part",
				"hair_color": "copper", "brow_style": "angled", "eye_style": "narrow",
				"eye_color": "sky", "nose_style": "angular", "mouth_style": "serious",
				"facial_hair": "none", "accessory": "hair_clip", "marking": "brow_scar",
				"outfit": "armor", "accent_palette": "cobalt", "facing": "left",
			},
		},
	},
	{
		"id": "milo",
		"name": "Milo Dash",
		"role": "Act II rival",
		"identity": "Heavy contact and fearless shortcuts in the Scrapjaw",
		"vehicle_id": "scrapjaw",
		"ai_style": {
			"corner_pace": 0.96, "brake_timing": 1.02, "boost_eagerness": 1.18,
			"overtake_aggression": 1.04, "shortcut_preference": 1.16, "line_commitment": 0.96,
		},
		"avatar_art": {
			"seed": 91004,
			"options": {
				"gender": "male",
				"face_shape": "square", "skin_tone": "cocoa", "hair_style": "buzz",
				"hair_color": "black", "brow_style": "thick", "eye_style": "wide",
				"eye_color": "amber", "nose_style": "broad", "mouth_style": "grin",
				"facial_hair": "stubble", "accessory": "none", "marking": "cheek_scar",
				"outfit": "armor", "accent_palette": "berry", "facing": "left",
			},
		},
	},
	{
		"id": "tess",
		"name": "Tess Circuit",
		"role": "Act III rival",
		"identity": "Long controlled drifts in the Flicker",
		"vehicle_id": "flicker",
		"ai_style": {
			"corner_pace": 1.01, "brake_timing": 1.1, "boost_eagerness": 0.94,
			"overtake_aggression": 0.9, "shortcut_preference": 0.96, "line_commitment": 1.1,
		},
		"avatar_art": {
			"seed": 91005,
			"options": {
				"gender": "female",
				"face_shape": "heart", "skin_tone": "olive", "hair_style": "locs",
				"hair_color": "auburn", "brow_style": "soft", "eye_style": "upturned",
				"eye_color": "violet", "nose_style": "button", "mouth_style": "smirk",
				"facial_hair": "none", "accessory": "earring", "marking": "beauty_spot",
				"outfit": "turtleneck", "accent_palette": "orchid", "facing": "left",
			},
		},
	},
	{
		"id": "cass",
		"name": "Cass Relay",
		"role": "Reigning champion",
		"identity": "Calm, fast, and dismissive until Rae earns respect",
		"vehicle_id": "flicker",
		"ai_style": {
			"corner_pace": 1.02, "brake_timing": 0.97, "boost_eagerness": 1.04,
			"overtake_aggression": 1.22, "shortcut_preference": 1.08, "line_commitment": 1.04,
		},
		"avatar_art": {
			"seed": 91006,
			"options": {
				"gender": "male",
				"face_shape": "long", "skin_tone": "ivory", "hair_style": "quiff",
				"hair_color": "silver", "brow_style": "angled", "eye_style": "narrow",
				"eye_color": "slate", "nose_style": "hooked", "mouth_style": "serious",
				"facial_hair": "stubble", "accessory": "none", "marking": "brow_scar",
				"outfit": "collared", "accent_palette": "marigold", "facing": "left",
			},
		},
	},
]

const VEHICLES := [
	{
		"id": "rustbug",
		"name": "Rustbug",
		"archetype": "Balanced",
		"strength": "Predictable recovery and all-round pace",
		"tradeoff": "No dominant specialty",
		"unlock": "Start",
		"tint": "f5d25c",
		"car_art": {
			"seed": 92001, "type": "compact",
			"options": {"palette": "citrus_pop", "parts": {
				"hood": "smooth", "cabin": "bubble", "bumpers": "utility",
				"wheels": "classic", "spoiler": "none", "livery": "center_stripe",
			}},
		},
		"stats_path": "res://data/vehicles/rustbug.tres",
		"ratings": {"speed": 0.944444, "grip": 0.84, "mass": 0.708333, "drift": 0.619048},
	},
	{
		"id": "pinbolt",
		"name": "Pinbolt",
		"archetype": "Grip",
		"strength": "Braking and technical corner speed",
		"tradeoff": "Lower drift boost and top speed",
		"unlock": "Win Act I",
		"tint": "71b7ff",
		"car_art": {
			"seed": 92002, "type": "coupe",
			"options": {"palette": "marina_blue", "parts": {
				"hood": "twin_vents", "cabin": "angular", "bumpers": "sport",
				"wheels": "mesh", "spoiler": "lip", "livery": "twin_stripe",
			}},
		},
		"stats_path": "res://data/vehicles/pinbolt.tres",
		"ratings": {"speed": 0.888889, "grip": 0.94, "mass": 0.65, "drift": 0.476190},
	},
	{
		"id": "scrapjaw",
		"name": "Scrapjaw",
		"archetype": "Heavy",
		"strength": "Stability, collisions, and straight-line speed",
		"tradeoff": "Slow turn-in and recovery",
		"unlock": "Win Act II",
		"tint": "db724d",
		"car_art": {
			"seed": 92003, "type": "muscle",
			"options": {"palette": "candy_red", "parts": {
				"hood": "power_scoop", "cabin": "panoramic", "bumpers": "utility",
				"wheels": "rugged", "spoiler": "none", "livery": "solid",
			}},
		},
		"stats_path": "res://data/vehicles/scrapjaw.tres",
		"ratings": {"speed": 0.972222, "grip": 0.90, "mass": 0.958333, "drift": 0.523810},
	},
	{
		"id": "flicker",
		"name": "Flicker",
		"archetype": "Drift",
		"strength": "Rotation and boost generation",
		"tradeoff": "Demands precise counter-steer",
		"unlock": "Complete championship",
		"tint": "ca78ff",
		"car_art": {
			"seed": 92004, "type": "buggy",
			"options": {"palette": "plum_soda", "parts": {
				"hood": "smooth", "cabin": "bubble", "bumpers": "sport",
				"wheels": "mesh", "spoiler": "wing", "livery": "side_flash",
			}},
		},
		"stats_path": "res://data/vehicles/flicker.tres",
		"ratings": {"speed": 0.923611, "grip": 0.72, "mass": 0.60, "drift": 0.904762},
	},
]

const ACTS := [
	{"id": "kitchen", "number": 1, "name": "Kitchen Qualifier", "final_event": "kitchen_clean_line", "unlock_vehicle": "pinbolt"},
	{"id": "workshop", "number": 2, "name": "Workshop League", "final_event": "workshop_heavy_metal", "unlock_vehicle": "scrapjaw"},
	{"id": "office", "number": 3, "name": "Office Final", "final_event": "office_last_light", "unlock_vehicle": "flicker"},
]

const EVENTS := [
	{
		"id": "kitchen_crumb_rush", "act": 1, "name": "Crumb Rush",
		"environment": "Kitchen Counter", "format": "2-lap circuit", "laps": 2,
		"theme": "kitchen", "reverse": false, "race_format": "circuit", "opponent_count": 3,
		"unlock": "Start", "gate": 0, "finale": false,
		"story": "Inez rolls the repaired Rustbug onto the counter: one clean run before the kettle clicks off.",
		"rival_line": "Juniper: Keep the crumbs behind you, rookie. They hide bad lines.",
		"opponents": ["juniper", "milo", "tess"],
	},
	{
		"id": "kitchen_mug_run", "act": 1, "name": "Mug Run",
		"environment": "Kitchen Counter reverse", "format": "3-lap circuit", "laps": 3,
		"theme": "kitchen", "reverse": true, "race_format": "circuit", "opponent_count": 3,
		"unlock": "10 act points", "gate": 10, "finale": false,
		"story": "The circuit turns back through the mug shadows, where every shortcut narrows to a saucer's edge.",
		"rival_line": "Juniper: Reverse lines expose every lazy turn. Show me yours.",
		"opponents": ["juniper", "milo", "cass"],
	},
	{
		"id": "kitchen_clean_line", "act": 1, "name": "The Clean Line",
		"environment": "Kitchen Counter", "format": "Rival duel, first to finish", "laps": 3,
		"theme": "kitchen", "reverse": false, "race_format": "rival_duel", "opponent_count": 1,
		"unlock": "20 act points; Pinbolt", "gate": 20, "finale": true,
		"story": "Juniper waits at the chalk line while Inez tightens one last wheel nut by hand.",
		"rival_line": "Juniper: Beat my clean line and the Pinbolt is yours to understand.",
		"opponents": ["juniper"],
	},
	{
		"id": "workshop_screw_loose", "act": 2, "name": "Screw Loose",
		"environment": "Workshop Bench", "format": "2-lap circuit", "laps": 2,
		"theme": "workshop", "reverse": false, "race_format": "circuit", "opponent_count": 3,
		"unlock": "Win Act I", "gate": 0, "finale": false,
		"story": "The workshop league starts between loose washers and a drill bit still warm from the day shift.",
		"rival_line": "Milo: If it rattles, it races. Try not to become another spare part.",
		"opponents": ["milo", "juniper", "cass"],
	},
	{
		"id": "workshop_ruler_drop", "act": 2, "name": "Ruler Drop",
		"environment": "Workshop Bench reverse", "format": "3-lap circuit", "laps": 3,
		"theme": "workshop", "reverse": true, "race_format": "circuit", "opponent_count": 3,
		"unlock": "10 act points", "gate": 10, "finale": false,
		"story": "A steel ruler bridges the return route, flexing under four tiny machines and one enormous wager.",
		"rival_line": "Milo: The ruler only feels narrow if you plan on braking.",
		"opponents": ["milo", "tess", "juniper"],
	},
	{
		"id": "workshop_heavy_metal", "act": 2, "name": "Heavy Metal",
		"environment": "Workshop Bench", "format": "Rival duel, first to finish", "laps": 3,
		"theme": "workshop", "reverse": false, "race_format": "rival_duel", "opponent_count": 1,
		"unlock": "20 act points; Scrapjaw", "gate": 20, "finale": true,
		"story": "Milo parks the Scrapjaw across the start stripe, grinning as the bench lamps hum awake.",
		"rival_line": "Milo: Win this and I stop calling that Rustbug a paperweight.",
		"opponents": ["milo"],
	},
	{
		"id": "office_paper_trail", "act": 3, "name": "Paper Trail",
		"environment": "Office Desk", "format": "2-lap circuit", "laps": 2,
		"theme": "office", "reverse": false, "race_format": "circuit", "opponent_count": 3,
		"unlock": "Win Act II", "gate": 0, "finale": false,
		"story": "Rae reaches the silent office with sunrise paling the blinds and Cass already watching the clock.",
		"rival_line": "Tess: Paper moves under pressure. So do drivers.",
		"opponents": ["tess", "cass", "milo"],
	},
	{
		"id": "office_keyboard_cut", "act": 3, "name": "Keyboard Cut",
		"environment": "Office Desk reverse", "format": "3-lap circuit", "laps": 3,
		"theme": "office", "reverse": true, "race_format": "circuit", "opponent_count": 3,
		"unlock": "10 act points", "gate": 10, "finale": false,
		"story": "The reverse route dives between keycaps, each gap daring Rae to trade patience for speed.",
		"rival_line": "Tess: Hold the drift past Enter. Lift early and Cass will notice.",
		"opponents": ["tess", "cass", "juniper"],
	},
	{
		"id": "office_last_light", "act": 3, "name": "Last Light Grand Final",
		"environment": "Office Desk", "format": "4-car, 4-lap final", "laps": 4,
		"theme": "office", "reverse": false, "race_format": "circuit", "opponent_count": 3,
		"unlock": "20 act points; Flicker and ending", "gate": 20, "finale": true,
		"story": "The last desk lamp burns above the Grand Household Circuit. One race decides whether rookies keep a place on it.",
		"rival_line": "Cass: You earned the grid, Rae. Now earn the circuit.",
		"opponents": ["cass", "tess", "milo"],
	},
]


static func score_for_finish(position: int) -> int:
	return int(POINTS_BY_FINISH.get(position, 0))


static func get_event(event_id: String) -> Dictionary:
	for event: Dictionary in EVENTS:
		if String(event["id"]) == event_id:
			return event.duplicate(true)
	return {}


static func get_act(act_number: int) -> Dictionary:
	for act: Dictionary in ACTS:
		if int(act["number"]) == act_number:
			return act.duplicate(true)
	return {}


static func get_vehicle(vehicle_id: String) -> Dictionary:
	for vehicle: Dictionary in VEHICLES:
		if String(vehicle["id"]) == vehicle_id:
			return vehicle.duplicate(true)
	return {}


static func get_driver(driver_id: String) -> Dictionary:
	for driver: Dictionary in CAST:
		if String(driver["id"]) == driver_id:
			return driver.duplicate(true)
	return {}


static func event_ids() -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in EVENTS:
		ids.append(String(event["id"]))
	return ids


static func vehicle_ids() -> Array[String]:
	var ids: Array[String] = []
	for vehicle: Dictionary in VEHICLES:
		ids.append(String(vehicle["id"]))
	return ids


static func act_points(progress: Dictionary, act_number: int) -> int:
	var total := 0
	var best_points: Dictionary = progress.get("best_event_points", {})
	for event: Dictionary in EVENTS:
		if int(event["act"]) == act_number:
			total += int(best_points.get(String(event["id"]), 0))
	return total


static func is_event_unlocked(event_id: String, progress: Dictionary) -> bool:
	var event := get_event(event_id)
	if event.is_empty():
		return false
	var act_number := int(event["act"])
	if act_number > 1 and not get_act(act_number - 1)["id"] in progress.get("completed_acts", []):
		return false
	return act_points(progress, act_number) >= int(event["gate"])


static func has_progress(progress: Dictionary) -> bool:
	return bool(progress.get("championship_started", false))


static func is_ending_pending(progress: Dictionary) -> bool:
	return "office" in progress.get("completed_acts", []) and not bool(progress.get("ending_seen", false))


static func apply_event_result(progress: Dictionary, event_id: String, position: int) -> Dictionary:
	var updated := progress.duplicate(true)
	var event := get_event(event_id)
	var summary := {
		"save": updated,
		"event_id": event_id,
		"new_best": false,
		"points_gained": 0,
		"act_completed": false,
		"ending_unlocked": false,
		"unlocked_vehicles": [],
	}
	if event.is_empty() or not POINTS_BY_FINISH.has(position):
		return summary

	var finishes: Dictionary = updated.get("best_event_finishes", {})
	var points: Dictionary = updated.get("best_event_points", {})
	var old_finish := int(finishes.get(event_id, 0))
	var old_points := int(points.get(event_id, 0))
	var new_points := score_for_finish(position)
	if old_finish == 0 or position < old_finish:
		finishes[event_id] = position
		summary["new_best"] = true
	if new_points > old_points:
		points[event_id] = new_points
		summary["points_gained"] = new_points - old_points
	updated["best_event_finishes"] = finishes
	updated["best_event_points"] = points

	var completed_events: Array = updated.get("completed_events", [])
	if not event_id in completed_events:
		completed_events.append(event_id)
	updated["completed_events"] = completed_events

	if bool(event["finale"]) and position == 1:
		var act := get_act(int(event["act"]))
		var completed_acts: Array = updated.get("completed_acts", [])
		var act_id := String(act["id"])
		if not act_id in completed_acts:
			completed_acts.append(act_id)
			summary["act_completed"] = true
		updated["completed_acts"] = completed_acts
		var unlocked: Array = updated.get("unlocked_vehicles", ["rustbug"])
		var vehicle_id := String(act["unlock_vehicle"])
		if not vehicle_id in unlocked:
			unlocked.append(vehicle_id)
			summary["unlocked_vehicles"].append(vehicle_id)
		updated["unlocked_vehicles"] = unlocked
		if int(event["act"]) == 3:
			summary["ending_unlocked"] = is_ending_pending(updated)

	summary["save"] = updated
	return summary


static func create_vehicle_stats(vehicle_id: String) -> VehicleStats:
	var vehicle := get_vehicle(vehicle_id)
	if vehicle.is_empty():
		vehicle = get_vehicle("rustbug")
	var stats_path := String(vehicle.get("stats_path", ""))
	var source := ResourceLoader.load(stats_path) as VehicleStats
	if source == null:
		push_error("Vehicle '%s' could not load VehicleStats from %s" % [String(vehicle.get("id", vehicle_id)), stats_path])
		return VehicleStats.new()
	var resource := source.duplicate(true) as VehicleStats
	for validation_error: String in resource.get_validation_errors():
		push_error("Vehicle '%s' has invalid physics data: %s" % [String(vehicle["id"]), validation_error])
	return resource
