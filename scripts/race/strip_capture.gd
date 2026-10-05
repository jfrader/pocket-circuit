extends RefCounted

const CAPTURE_RANGE := 90.0
const CAPTURE_SECONDS := 1.5

var exposure := 0.0


func advance(delta: float, distance: float, same_section: bool, clear_sight: bool, suspended: bool) -> bool:
	if suspended or distance > CAPTURE_RANGE or not same_section or not clear_sight:
		exposure = 0.0
		return false
	exposure += delta
	return exposure + 0.00001 >= CAPTURE_SECONDS


func clear() -> void:
	exposure = 0.0


func fraction() -> float:
	return clampf(exposure / CAPTURE_SECONDS, 0.0, 1.0)
