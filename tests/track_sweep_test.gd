extends SceneTree

const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")
const FIXTURE_LAYER := 4

var _viewport: SubViewport
var _space: PhysicsDirectSpaceState2D
var _fixture: StaticBody2D
var _collision: CollisionShape2D
var _sweep: PhysicsShapeQueryParameters2D
var _point: PhysicsPointQueryParameters2D
var _ray: PhysicsRayQueryParameters2D
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_root().add_child(_viewport)
	_fixture = StaticBody2D.new()
	_fixture.collision_layer = FIXTURE_LAYER
	_fixture.collision_mask = 0
	_collision = CollisionShape2D.new()
	_fixture.add_child(_collision)
	_viewport.add_child(_fixture)
	_space = _viewport.world_2d.direct_space_state
	_sweep = PhysicsShapeQueryParameters2D.new()
	_sweep.collision_mask = FIXTURE_LAYER
	_sweep.collide_with_bodies = true
	_sweep.collide_with_areas = false
	_sweep.margin = 0.0
	_point = PhysicsPointQueryParameters2D.new()
	_point.collision_mask = FIXTURE_LAYER
	_point.collide_with_bodies = true
	_point.collide_with_areas = false
	_ray = PhysicsRayQueryParameters2D.new()
	_ray.collision_mask = FIXTURE_LAYER
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	_ray.hit_from_inside = true

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
			if not await _compare(line, center, size, kind, rotation, clearance, "sample=%d" % sample):
				_finish(false)
				return
	for points: PackedVector2Array in [PackedVector2Array([Vector2(-200,0),Vector2(200,0)]), PackedVector2Array([Vector2(0,-200),Vector2(0,200)]), PackedVector2Array([Vector2.ZERO,Vector2.ZERO])]:
		for kind: StringName in [&"circle", &"rect"]:
			if not await _compare(points, Vector2.ZERO, Vector2(10,10), kind, 0, 0, "axis/zero-span points=%s" % str(points)):
				_finish(false)
				return
	var corner_clear := PackedVector2Array([Vector2(1025,25), Vector2(1026,25)])
	var corner_hit := PackedVector2Array([Vector2(1022,22), Vector2(1023,22)])
	var edge_clear := PackedVector2Array([Vector2(1029,0), Vector2(1030,0)])
	var edge_hit := PackedVector2Array([Vector2(1027,0), Vector2(1028,0)])
	for fixture: Dictionary in [
		{"line": corner_clear, "kind": &"rect", "expected": true, "label": "rounded rect corner clear"},
		{"line": corner_hit, "kind": &"rect", "expected": false, "label": "rounded rect corner hit"},
		{"line": edge_clear, "kind": &"rect", "expected": true, "label": "rect margin clear"},
		{"line": edge_hit, "kind": &"rect", "expected": false, "label": "rect margin hit"},
		{"line": edge_clear, "kind": &"circle", "expected": true, "label": "circle margin clear"},
		{"line": edge_hit, "kind": &"circle", "expected": false, "label": "circle margin hit"},
	]:
		var fixture_line: PackedVector2Array = fixture["line"]
		var kind: StringName = fixture["kind"]
		var label: String = fixture["label"]
		if not await _compare(fixture_line, Vector2(1000,0), Vector2(20,20), kind, 0, 18, label, fixture["expected"]):
			_finish(false)
			return
	print("TRACK_SWEEP_TEST PASS")
	_finish(true)


func _compare(line: PackedVector2Array, center: Vector2, size: Vector2, kind: StringName, rotation: float, clearance: float, label: String, expected: Variant = null) -> bool:
	var shape: Shape2D
	if kind == &"circle":
		var circle := CircleShape2D.new()
		circle.radius = maxf(size.x, size.y) * 0.5
		shape = circle
	else:
		var rectangle := RectangleShape2D.new()
		rectangle.size = size
		shape = rectangle
	_collision.shape = shape
	_fixture.global_position = center
	_fixture.global_rotation = rotation
	await physics_frame
	await process_frame
	_point.position = center
	var registered := false
	for hit: Dictionary in _space.intersect_point(_point, 8):
		if hit.get("rid") == _fixture.get_rid():
			registered = true
	if not _check(registered, "%s fixture not registered at center=%s kind=%s" % [label, center, kind]):
		return false
	var actual := GEOMETRY.line_sweep_clears_footprint(line, center, size, kind, rotation, clearance)
	var reference := _reference(line, clearance)
	if _failed:
		return false
	if not _check(actual == reference, "%s kind=%s center=%s size=%s rotation=%s clearance=%s actual=%s physics=%s line=%s" % [label, kind, center, size, rotation, clearance, actual, reference, str(line) if line.size() < 4 else "128-point loop"]):
		return false
	return expected == null or _check(reference == expected, "%s physics=%s expected=%s" % [label, reference, expected])


func _reference(line: PackedVector2Array, clearance: float) -> bool:
	if clearance > 0.0:
		var circle := CircleShape2D.new()
		circle.radius = clearance
		_sweep.shape = circle
		for index in line.size():
			var from := line[index]
			var to := line[(index + 1) % line.size()]
			_sweep.transform = Transform2D(0.0, from)
			_sweep.motion = Vector2.ZERO
			if not _space.intersect_shape(_sweep, 1).is_empty():
				return false
			_sweep.motion = to - from
			var fractions: PackedFloat32Array = _space.cast_motion(_sweep)
			if not _check(fractions.size() == 2, "cast_motion malformed at segment=%d fractions=%s" % [index, fractions]):
				return false
			if fractions[1] < 1.0:
				return false
			_sweep.motion = Vector2.ZERO
			_sweep.transform = Transform2D(0.0, to)
			if not _space.intersect_shape(_sweep, 1).is_empty():
				return false
	else:
		for index in line.size():
			var from := line[index]
			var to := line[(index + 1) % line.size()]
			_point.position = from
			if not _space.intersect_point(_point, 1).is_empty():
				return false
			_ray.from = from
			_ray.to = to
			if not _space.intersect_ray(_ray).is_empty():
				return false
		_point.position = line[line.size() - 1]
		if not _space.intersect_point(_point, 1).is_empty():
			return false
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("TRACK_SWEEP_TEST FAIL: " + message)
	return condition


func _finish(ok: bool) -> void:
	_viewport.free()
	quit(0 if ok else 1)
