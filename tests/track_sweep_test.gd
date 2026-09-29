extends SceneTree

const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1291
	var line := PackedVector2Array()
	for index in 128:
		line.append(Vector2.from_angle(float(index) / 128.0 * TAU) * rng.randf_range(900.0, 1100.0))
	for sample in 512:
		var center := Vector2(rng.randf_range(-1500,1500), rng.randf_range(-1500,1500))
		var size := Vector2(rng.randf_range(1,350), rng.randf_range(1,350))
		var rotation := rng.randf_range(-PI, PI)
		var clearance := rng.randf_range(0,180)
		for kind: StringName in [&"circle", &"rect"]:
			assert(GEOMETRY.line_sweep_clears_footprint(line,center,size,kind,rotation,clearance) == _reference(line,center,size,kind,rotation,clearance), "broad phase must preserve exact sweep results")
	for points: PackedVector2Array in [PackedVector2Array([Vector2(-200,0),Vector2(200,0)]), PackedVector2Array([Vector2(0,-200),Vector2(0,200)]), PackedVector2Array([Vector2.ZERO,Vector2.ZERO])]:
		for kind: StringName in [&"circle", &"rect"]:
			assert(GEOMETRY.line_sweep_clears_footprint(points,Vector2.ZERO,Vector2(10,10),kind,0,0) == _reference(points,Vector2.ZERO,Vector2(10,10),kind,0,0))
	print("TRACK_SWEEP_TEST PASS broad_phase_matches_exhaustive_reference")
	quit(0)

static func _reference(line: PackedVector2Array, center: Vector2, size: Vector2, kind: StringName, rotation: float, clearance: float) -> bool:
	if kind == &"circle":
		for index in line.size():
			if GEOMETRY.point_to_segment_distance(center,line[index],line[(index+1)%line.size()]) < maxf(size.x,size.y)*0.5+clearance:
				return false
		return true
	for index in line.size():
		if GEOMETRY.segment_intersects_axis_rect((line[index]-center).rotated(-rotation),(line[(index+1)%line.size()]-center).rotated(-rotation),size*0.5+Vector2.ONE*clearance):
			return false
	return true
