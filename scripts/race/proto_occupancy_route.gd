class_name ProtoOccupancyRoute
## PROTOTYPE (scratch only): route anchors from the outline of a seeded,
## hole-free, saddle-free cell blob on an uneven sheared lattice. Same return
## contract as TrackRouteGrammar.construct.

const GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const MIN_CELL := 470.0
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


static func construct(seed: int, bounds: Rect2, target_length: float, max_length: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shear := rng.randf_range(-0.28, 0.28) * minf(bounds.size.x, bounds.size.y) / maxf(bounds.size.x, bounds.size.y) if rng.randf() < 0.6 else 0.0
	var width := bounds.size.x - absf(shear) * bounds.size.y
	var spine := OS.get_environment("PC_PROTO_SPINE") == "1"
	var cell_size := MIN_CELL
	if spine:
		cell_size = maxf(MIN_CELL, minf(width, bounds.size.y) / rng.randf_range(5.0, 7.0))
	var cols := maxi(3, floori(width / cell_size))
	var rows := maxi(3, floori(bounds.size.y / cell_size))
	var xs := _lattice(rng, cols, width, -width * 0.5, cell_size)
	var ys := _lattice(rng, rows, bounds.size.y, -bounds.size.y * 0.5, cell_size)
	var cells := {}
	var start := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
	cells[start] = true
	if spine:
		var row := rng.randi_range(1, rows - 2)
		var from := rng.randi_range(0, maxi(0, cols / 5))
		var to := cols - 1 - rng.randi_range(0, maxi(0, cols / 5))
		cells.clear()
		for x in range(from, to + 1):
			cells[Vector2i(x, row)] = true
	var rejected := {}
	var branchy := OS.get_environment("PC_PROTO_GROWTH") == "branchy"
	var stop_length := minf(target_length, max_length * 0.97)
	while true:
		var frontier: Array[Vector2i] = []
		for cell: Vector2i in cells:
			for d: Vector2i in DIRS:
				var n := cell + d
				if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not cells.has(n) and not rejected.has(n):
					frontier.append(n)
		if frontier.is_empty():
			break
		var pick := frontier[rng.randi_range(0, frontier.size() - 1)]
		if branchy:
			var tips: Array[Vector2i] = []
			for n: Vector2i in frontier:
				var touching := 0
				for d: Vector2i in DIRS:
					touching += 1 if cells.has(n + d) else 0
				if touching == 1:
					tips.append(n)
			if not tips.is_empty():
				pick = tips[rng.randi_range(0, tips.size() - 1)]
		cells[pick] = true
		var loop := _outline(cells, xs, ys, shear)
		if loop.is_empty() or _length(loop) > max_length * 0.97:
			cells.erase(pick)
			rejected[pick] = true
			continue
		rejected.clear()
		if _length(loop) >= stop_length:
			break
	var anchors := GRAMMAR._drop_collinear_anchors(_outline(cells, xs, ys, shear))
	anchors = GRAMMAR._compound_chamfer(anchors, seed, 3, false)
	var heading := rng.randf_range(-0.12, 0.12) * pow(minf(bounds.size.x, bounds.size.y) / maxf(bounds.size.x, bounds.size.y), 2.0)
	for i in anchors.size():
		anchors[i] = bounds.get_center() + anchors[i].rotated(heading)
	var radii := PackedFloat32Array()
	for i in anchors.size():
		radii.append(rng.randf_range(GRAMMAR.CORNER_RADIUS, 260.0))
	return {"program": &"occupancy", "recipe": StringName("occupancy_%08x" % (seed & 0x7FFFFFFF)), "anchors": anchors, "radii": radii}


static func _lattice(rng: RandomNumberGenerator, count: int, span: float, origin: float, cell: float) -> PackedFloat32Array:
	var weights: Array[float] = []
	var total := 0.0
	for i in count:
		var w := rng.randf_range(1.0, 1.9)
		weights.append(w)
		total += w
	var free := span - cell * count
	var lines := PackedFloat32Array([origin])
	for w: float in weights:
		lines.append(lines[lines.size() - 1] + cell + free * w / total)
	return lines


## Counter-clockwise outline, or empty when the blob has a hole or a diagonal
## saddle (either would make the route fold or touch itself).
static func _outline(cells: Dictionary, xs: PackedFloat32Array, ys: PackedFloat32Array, shear: float) -> PackedVector2Array:
	for cell: Vector2i in cells:
		for d in [Vector2i(1, 1), Vector2i(-1, 1)]:
			var diagonal: Vector2i = cell + d
			if cells.has(diagonal) and not cells.has(Vector2i(diagonal.x, cell.y)) and not cells.has(Vector2i(cell.x, diagonal.y)):
				return PackedVector2Array()
	var next := {}
	var edge_count := 0
	for cell: Vector2i in cells:
		var corners := [cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
		for side in 4:
			if not cells.has(cell + DIRS[(side + 3) % 4]):
				next[corners[side]] = corners[(side + 1) % 4]
				edge_count += 1
	var first: Vector2i = next.keys()[0]
	var cursor := first
	var loop := PackedVector2Array()
	for step in edge_count:
		loop.append(Vector2(xs[cursor.x] + ys[cursor.y] * shear, ys[cursor.y]))
		cursor = next[cursor]
		if cursor == first:
			return loop if step == edge_count - 1 else PackedVector2Array()
	return PackedVector2Array()


static func _length(loop: PackedVector2Array) -> float:
	var total := 0.0
	for i in loop.size():
		total += loop[i].distance_to(loop[(i + 1) % loop.size()])
	return total
