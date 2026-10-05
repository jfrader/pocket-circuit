extends RefCounted
## Signed lane IDs, relative to the route's north tangent: -2/-1 travel south
## on its left; +1/+2 travel north on its right. Unknown IDs use northbound +1.
## The plan keeps {arc, lane, speed, behavior, vehicle_id}; direction is derived.

const LANE_WIDTH := 120.0
const HALF_WIDTH := LANE_WIDTH * 2.0
const LANES := [-2, -1, 1, 2]
const NORTHBOUND := [1, 2]
const SOUTHBOUND := [-2, -1]
const NORTH_RACING_OFFSET := LANE_WIDTH


static func lane_id(value: float) -> int:
	if not is_finite(value) or value != floorf(value):
		return 1
	var lane := int(value)
	return lane if lane in LANES else 1


static func direction(value: float) -> int:
	return -1 if lane_id(value) < 0 else 1


static func fraction(value: float) -> float:
	var lane := lane_id(value)
	return signf(lane) * (float(abs(lane)) - 0.5) * 0.5


static func lane_fractions(travel_direction: int) -> Array[float]:
	return [-0.25, -0.75] if travel_direction < 0 else [0.25, 0.75]
