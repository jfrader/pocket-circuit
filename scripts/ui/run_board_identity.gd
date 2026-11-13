extends RefCounted

const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")


static func look(session: RunSession, stop_id: String) -> Dictionary:
	var kind := String(session.current_map.get_node(stop_id).get("type", ""))
	if kind not in RunSession.RACE_NODE_TYPES:
		return {}
	var assignment := session.opponents_for_node(stop_id)
	var opponents: Array = assignment.get("opponents", [])
	if opponents.is_empty():
		return {"key": session.current_car_id, "source": "player", "texture": MATERIALS.hero_texture(session.current_car_id)}
	var leader: Dictionary = opponents[0]
	var vehicle_id := String(leader["vehicle_id"])
	return {"key": vehicle_id, "source": "opponent", "opponent_id": String(leader["id"]), "texture": MATERIALS.hero_texture(vehicle_id)}
