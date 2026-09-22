class_name V8TrackModuleCatalogData
extends RefCounted


static func definitions() -> Array[Dictionary]:
	return [
		_definition(&"straight_link", &"straight", {"length": [180.0, 2400.0]}, [&"connection"], [&"S(length)"]),
		_definition(&"straight_setup", &"straight", {"length": [520.0, 2400.0], "finish_length": [1000.0, 2400.0]}, [&"speed", &"finish", &"setup"], [&"S(length)"]),
		_definition(&"corner_tight", &"corner", {"radius": [180.0, 260.0], "angles_deg": [45, 90, 135]}, [&"technical", &"conflict"], [&"A(radius,angle)"], [&"radius"]),
		_definition(&"corner_medium", &"corner", {"radius": [260.0, 520.0], "angles_deg": [45, 90, 135]}, [&"opening", &"technical", &"conflict"], [&"A(radius,angle)"], [&"radius"]),
		_definition(&"corner_sweeper", &"corner", {"radius": [520.0, 1000.0], "angles_deg": [45, 90, 135]}, [&"speed", &"opening"], [&"A(radius,angle)"]),
		_definition(&"corner_opening", &"profile", {"inner_radius": [180.0, 560.0], "outer_radius": [225.0, 700.0], "ratio_min": 1.25, "split": [0.35, 0.5, 0.65], "angles_deg": [45, 90, 135]}, [&"opening", &"speed"], [&"A(inner_radius,angle*split)", &"A(outer_radius,angle*(1-split))"]),
		_definition(&"corner_tightening", &"profile", {"inner_radius": [180.0, 560.0], "outer_radius": [225.0, 700.0], "ratio_min": 1.25, "split": [0.35, 0.5, 0.65], "angles_deg": [45, 90, 135]}, [&"technical", &"conflict"], [&"A(outer_radius,angle*split)", &"A(inner_radius,angle*(1-split))"]),
		_definition(&"u_return", &"return", {"radius": [180.0, 520.0]}, [&"technical", &"return"], [&"A(radius,+/-PI)"]),
		_definition(&"s_offset", &"offset", {"radius": [180.0, 520.0], "distance": [180.0, 900.0], "angles_deg": [30, 45, 60]}, [&"opening", &"technical"], [&"A(radius,angle)", &"S(distance)", &"A(radius,-angle)"]),
		_definition(&"chicane_return", &"chicane", {"radius": [180.0, 520.0], "distance": [180.0, 900.0], "angles_deg": [30, 45, 60]}, [&"conflict", &"technical"], [&"A(radius,angle)", &"A(radius,-angle)", &"S(distance)", &"A(radius,-angle)", &"A(radius,angle)"]),
		_definition(&"switchback", &"switchback", {"radius": [180.0, 360.0], "depth_1": [450.0, 1600.0], "depth_2": [450.0, 1600.0], "width": [400.0, 1200.0]}, [&"technical", &"conflict", &"return"], [&"A(radius,+90)", &"S(depth_1)", &"A(radius,-90)", &"S(width)", &"A(radius,-90)", &"S(depth_2)", &"A(radius,+90)"]),
	]


static func _definition(id: StringName, family: StringName, domains: Dictionary, tags: Array[StringName], recipe: Array[StringName], exclusive_maxima: Array[StringName] = []) -> Dictionary:
	return {
		"id": id,
		"revision": 1,
		"family": family,
		"parameter_domains": domains,
		"exclusive_maxima": exclusive_maxima,
		"allowed_moment_tags": tags,
		"primitive_recipe": recipe,
		"supports_mirror": true,
		"supports_reverse": true,
	}
