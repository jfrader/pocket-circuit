class_name TrackCornerMap
## Where the lap is calm enough for slippery surfaces and on-course obstacles.
## Races run both directions, so a spot is calm only when it is far from every
## corner ahead and behind: the braking zone in one direction is the corner exit
## in the other. Pure and deterministic.

const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")

## A sample is in a corner when the heading turns more than CORNER_TURN (~29°)
## over CORNER_SPAN samples each side (~175 units at the 35-unit spacing). That
## flags about a quarter of a lap; gentle sweeps stay open.
const CORNER_SPAN := 5
const CORNER_TURN := 0.5
## Calm means at least this far along the lap from any corner sample. The
## detector already flags a little before the curve begins, so this keeps
## roughly the 300-unit braking zone clear.
const CORNER_CLEARANCE := 250.0


## Arc distance from each sample to the nearest corner sample, ahead or behind;
## 0 inside a corner. INF on a lap with no corner.
static func clearances(centerline: PackedVector2Array) -> PackedFloat32Array:
	var n := centerline.size()
	var result := PackedFloat32Array()
	result.resize(n)
	result.fill(INF)
	if n < CORNER_SPAN * 2 + 1:
		return result
	var steps := PackedFloat32Array()
	steps.resize(n)
	for i in n:
		steps[i] = centerline[i].distance_to(centerline[(i + 1) % n])
		if GEOMETRY.turn_strength(centerline, i, CORNER_SPAN) > CORNER_TURN:
			result[i] = 0.0
	# Two laps each way let the running distance wrap past the start.
	for pass_index in n * 2:
		var i := pass_index % n
		var previous := posmod(i - 1, n)
		result[i] = minf(result[i], result[previous] + steps[previous])
	for pass_index in n * 2:
		var i := n - 1 - (pass_index % n)
		var next := (i + 1) % n
		result[i] = minf(result[i], result[next] + steps[i])
	return result


## True when every sample within `half_span` of `index` is calm.
static func is_calm(clearance: PackedFloat32Array, index: int, half_span: int) -> bool:
	var n := clearance.size()
	for offset in range(-half_span, half_span + 1):
		if clearance[posmod(index + offset, n)] < CORNER_CLEARANCE:
			return false
	return true


## Calm centre indices for an item spanning `half_span` samples each side.
static func calm_indices(clearance: PackedFloat32Array, half_span: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for index in clearance.size():
		if is_calm(clearance, index, half_span):
			indices.append(index)
	return indices
