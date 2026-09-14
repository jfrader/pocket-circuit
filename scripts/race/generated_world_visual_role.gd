class_name GeneratedWorldVisualRole
extends RefCounted

const META_KEY := &"visual_role"
const SOLID := &"SOLID"
const FLAT := &"FLAT"
const MOVING_HAZARD := &"MOVING_HAZARD"
const VALUES: Array[StringName] = [SOLID, FLAT, MOVING_HAZARD]


static func assign(node: Node, role: StringName) -> void:
	if role not in VALUES:
		push_error("Unknown generated world visual role: %s" % String(role))
		return
	node.set_meta(META_KEY, role)


static func read(node: Node) -> StringName:
	return StringName(node.get_meta(META_KEY, &""))


static func is_valid(node: Node) -> bool:
	return read(node) in VALUES