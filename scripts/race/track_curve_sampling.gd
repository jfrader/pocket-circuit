class_name TrackCurveSampling
## Arc-length uniform sampler for closed Catmull-Rom control loops (no endpoint duplicate).
## Pure, deterministic, no side effects or scaling.

const DEFAULT_MAX_SPACING := 35.0
const DEFAULT_MIN_COUNT := 260

const MAX_MIN_COUNT := 1000000
const MAX_DENSE_POINTS := 200000
const MAX_OUTPUT_POINTS := 100000


static func sample(controls: PackedVector2Array, maximum_spacing: float = DEFAULT_MAX_SPACING, minimum_count: int = DEFAULT_MIN_COUNT) -> PackedVector2Array:
	if controls.size() < 4:
		return PackedVector2Array()
	for p: Vector2 in controls:
		if !is_finite(p.x) or !is_finite(p.y):
			return PackedVector2Array()
	if !is_finite(maximum_spacing) or maximum_spacing <= 0.0 or !is_finite(minimum_count) or minimum_count < 1 or minimum_count > MAX_MIN_COUNT:
		return PackedVector2Array()

	var dense := _build_dense(controls)
	if dense.size() < 2:
		return PackedVector2Array()

	var cumuls := PackedFloat64Array([0.0])
	for i in range(1, dense.size()):
		cumuls.append(cumuls[cumuls.size() - 1] + dense[i - 1].distance_to(dense[i]))
	var close_dist := dense[dense.size() - 1].distance_to(dense[0])
	var total := cumuls[cumuls.size() - 1] + close_dist
	if total < 0.001 or !is_finite(total):
		return PackedVector2Array()

	var n := maxi(minimum_count, ceili(total / maximum_spacing))
	if n > MAX_OUTPUT_POINTS:
		return PackedVector2Array()

	var samples := PackedVector2Array()
	samples.append(dense[0])
	var target: float = 0.0
	var seg := 0
	for k in range(1, n):
		target = float(k) * total / float(n)
		if target > cumuls[cumuls.size() - 1]:
			var frac := (target - cumuls[cumuls.size() - 1]) / maxf(close_dist, 0.001)
			samples.append(dense[dense.size() - 1].lerp(dense[0], frac))
		else:
			while seg < dense.size() - 1 and cumuls[seg + 1] < target:
				seg += 1
			var frac := (target - cumuls[seg]) / maxf(cumuls[seg + 1] - cumuls[seg], 0.001)
			samples.append(dense[seg].lerp(dense[seg + 1], frac))
	return samples


static func sample_open(controls: PackedVector2Array, maximum_spacing: float = DEFAULT_MAX_SPACING) -> PackedVector2Array:
	if controls.size() < 2 or not is_finite(maximum_spacing) or maximum_spacing <= 0.0:
		return PackedVector2Array()
	var dense := PackedVector2Array([controls[0]])
	for index in controls.size() - 1:
		var a := controls[index]
		var b := controls[index + 1]
		if not a.is_finite() or not b.is_finite():
			return PackedVector2Array()
		var count := maxi(8, ceili(a.distance_to(b) / 6.0))
		if dense.size() + count > MAX_DENSE_POINTS:
			return PackedVector2Array()
		for step in range(1, count + 1):
			var t := float(step) / count
			var p0 := controls[maxi(0, index - 1)]
			var p3 := controls[mini(controls.size() - 1, index + 2)]
			dense.append(_catmull_point(p0, a, b, p3, t))
	var cumulative := PackedFloat64Array([0.0])
	for index in range(1, dense.size()):
		cumulative.append(cumulative[-1] + dense[index - 1].distance_to(dense[index]))
	var total := cumulative[-1]
	if total < 0.001 or ceili(total / maximum_spacing) + 1 > MAX_OUTPUT_POINTS:
		return PackedVector2Array()
	var count := maxi(1, ceili(total / maximum_spacing))
	var result := PackedVector2Array([controls[0]])
	var segment := 0
	for index in range(1, count):
		var target := total * float(index) / count
		while segment + 1 < cumulative.size() - 1 and cumulative[segment + 1] < target:
			segment += 1
		result.append(dense[segment].lerp(dense[segment + 1], (target - cumulative[segment]) / maxf(cumulative[segment + 1] - cumulative[segment], 0.001)))
	result.append(controls[-1])
	return result


static func _catmull_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


static func _build_dense(controls: PackedVector2Array) -> PackedVector2Array:
	var n := controls.size()
	var dense := PackedVector2Array()
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var p0 := _catmull_rom_closed(controls, t0)
		var p1 := _catmull_rom_closed(controls, t1)
		var chord := p0.distance_to(p1)
		if !is_finite(chord) or chord < 0.0:
			return PackedVector2Array()
		var subs := maxi(16, ceili(chord / 3.0))
		if dense.size() + subs > MAX_DENSE_POINTS:
			return PackedVector2Array()
		for s in subs:
			var tt := t0 + (t1 - t0) * float(s) / float(subs)
			dense.append(_catmull_rom_closed(controls, tt))
	return dense


static func _catmull_rom_closed(points: PackedVector2Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var index := int(floor(scaled))
	var local := scaled - float(index)
	var p0: Vector2 = points[posmod(index - 1, count)]
	var p1: Vector2 = points[posmod(index, count)]
	var p2: Vector2 = points[posmod(index + 1, count)]
	var p3: Vector2 = points[posmod(index + 2, count)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * local
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * local * local
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * local * local * local
	)
