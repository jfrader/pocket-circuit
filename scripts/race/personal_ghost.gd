class_name PersonalGhost
extends Node2D

const STORAGE_VERSION := 1
const SAMPLE_INTERVAL := 0.1
const MAX_GHOSTS := 12
const MAX_SAMPLES := 3600
const MASTERY := preload("res://scripts/progression/mastery_run.gd")

var _samples: Array = []
var _cursor := 0


static func normalize_ghosts(value: Variant) -> Array:
	var output: Array = []
	if value is not Array:
		return output
	for item: Variant in value:
		var ghost := normalize_ghost(item)
		if ghost.is_empty():
			continue
		var key := MASTERY.identity_key(ghost["identity"])
		var existing_index := -1
		for index in output.size():
			if MASTERY.identity_key(output[index]["identity"]) == key:
				existing_index = index
				break
		if existing_index < 0:
			output.append(ghost)
		elif float(ghost["race_time"]) < float(output[existing_index]["race_time"]):
			output[existing_index] = ghost
	while output.size() > MAX_GHOSTS:
		output.pop_front()
	return output


static func normalize_ghost(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var raw := value as Dictionary
	if int(raw.get("version", 0)) != STORAGE_VERSION:
		return {}
	var identity := MASTERY.normalize_identity(raw.get("identity"))
	var race_time := snappedf(_valid_number(raw.get("race_time"), 0.0, MASTERY.MAX_RECORDED_TIME), 0.001)
	var interval := _valid_number(raw.get("sample_interval"), 0.01, 1.0)
	var samples := finalize_samples(raw.get("samples"), race_time, interval)
	if identity.is_empty() or is_nan(race_time) or is_nan(interval) or race_time <= 0.0 or interval <= 0.0 or samples.size() < 2:
		return {}
	return {
		"version": STORAGE_VERSION,
		"identity": identity,
		"race_time": race_time,
		"sample_interval": interval,
		"samples": samples,
	}


static func normalize_samples(value: Variant) -> Array:
	var output: Array = []
	if value is not Array:
		return output
	var previous_time := -1.0
	for item: Variant in value:
		if output.size() >= MAX_SAMPLES:
			break
		if item is not Array or (item as Array).size() != 4:
			return []
		var raw := item as Array
		var time := _valid_number(raw[0], 0.0, MASTERY.MAX_RECORDED_TIME, true)
		var x := _valid_number(raw[1], -1000000.0, 1000000.0, true)
		var y := _valid_number(raw[2], -1000000.0, 1000000.0, true)
		var rotation := _valid_number(raw[3], -TAU * 100.0, TAU * 100.0, true)
		if is_nan(time) or time < 0.0 or time <= previous_time or is_nan(x) or is_nan(y) or is_nan(rotation):
			return []
		output.append([time, x, y, rotation])
		previous_time = time
	return output


static func finalize_samples(value: Variant, race_time: float, interval: float = SAMPLE_INTERVAL) -> Array:
	var finish_time := snappedf(race_time, 0.001)
	if is_nan(finish_time) or is_inf(finish_time) or is_nan(interval) or is_inf(interval) or finish_time <= 0.0 or interval <= 0.0:
		return []
	var samples := normalize_samples(value)
	if samples.size() < 2 or float(samples[0][0]) > 0.001:
		return []
	if float(samples.back()[0]) < finish_time - interval - 0.001:
		return []
	var output: Array = []
	for item: Array in samples:
		var sample_time := float(item[0])
		if sample_time < finish_time - 0.0005:
			output.append(item.duplicate())
			continue
		if is_equal_approx(sample_time, finish_time):
			var exact := item.duplicate()
			exact[0] = finish_time
			output.append(exact)
			return output
		if output.is_empty():
			return []
		var previous: Array = output.back()
		var duration := sample_time - float(previous[0])
		var weight := clampf((finish_time - float(previous[0])) / duration, 0.0, 1.0) if duration > 0.000001 else 1.0
		output.append(sample(
			finish_time,
			Transform2D(
				lerp_angle(float(previous[3]), float(item[3]), weight),
				Vector2(float(previous[1]), float(previous[2])).lerp(Vector2(float(item[1]), float(item[2])), weight)
			)
		))
		return output
	var last: Array = output.back()
	if is_equal_approx(float(last[0]), finish_time):
		last[0] = finish_time
		output[output.size() - 1] = last
	else:
		output.append([finish_time, last[1], last[2], last[3]])
	return output


static func sample(time: float, transform: Transform2D) -> Array:
	return [
		snappedf(maxf(0.0, time), 0.001),
		snappedf(transform.origin.x, 0.1),
		snappedf(transform.origin.y, 0.1),
		snappedf(transform.get_rotation(), 0.0001),
	]


static func store_best(ghosts_value: Variant, identity: Dictionary, race_time: float, samples_value: Variant) -> Dictionary:
	var ghosts := normalize_ghosts(ghosts_value)
	var candidate := normalize_ghost({
		"version": STORAGE_VERSION,
		"identity": identity,
		"race_time": race_time,
		"sample_interval": SAMPLE_INTERVAL,
		"samples": samples_value,
	})
	if candidate.is_empty():
		return {"ghosts": ghosts, "saved": false}
	var key := MASTERY.identity_key(candidate["identity"])
	for index in ghosts.size():
		if MASTERY.identity_key(ghosts[index]["identity"]) != key:
			continue
		if float(ghosts[index]["race_time"]) <= float(candidate["race_time"]):
			return {"ghosts": ghosts, "saved": false}
		ghosts.remove_at(index)
		break
	ghosts.append(candidate)
	while ghosts.size() > MAX_GHOSTS:
		ghosts.pop_front()
	return {"ghosts": ghosts, "saved": true}


static func compatible_best(ghosts_value: Variant, identity: Dictionary) -> Dictionary:
	var key := MASTERY.identity_key(identity)
	if key.is_empty():
		return {}
	for ghost: Dictionary in normalize_ghosts(ghosts_value):
		if MASTERY.identity_key(ghost["identity"]) == key:
			return ghost.duplicate(true)
	return {}


func configure(ghost_value: Variant, texture: Texture2D) -> bool:
	var ghost := normalize_ghost(ghost_value)
	if ghost.is_empty() or texture == null:
		return false
	_samples = ghost["samples"].duplicate(true)
	_cursor = 0
	var sprite := Sprite2D.new()
	sprite.name = "GhostCar"
	sprite.texture = texture
	sprite.scale = Vector2.ONE * 0.5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = Color(0.45, 0.9, 1.0, 0.38)
	sprite.show_behind_parent = true
	add_child(sprite)
	z_index = 3
	set_playback_time(0.0)
	return true


func set_playback_time(time: float) -> void:
	if _samples.is_empty():
		return
	while _cursor + 1 < _samples.size() and float(_samples[_cursor + 1][0]) <= time:
		_cursor += 1
	while _cursor > 0 and float(_samples[_cursor][0]) > time:
		_cursor -= 1
	var from: Array = _samples[_cursor]
	var to: Array = _samples[mini(_cursor + 1, _samples.size() - 1)]
	var duration := float(to[0]) - float(from[0])
	var weight := clampf((time - float(from[0])) / duration, 0.0, 1.0) if duration > 0.0001 else 0.0
	position = Vector2(float(from[1]), float(from[2])).lerp(Vector2(float(to[1]), float(to[2])), weight)
	rotation = lerp_angle(float(from[3]), float(to[3]), weight)
	visible = time <= float(_samples.back()[0]) + 0.001


static func _valid_number(value: Variant, minimum: float, maximum: float, allow_zero: bool = false) -> float:
	if value is not int and value is not float:
		return NAN
	var number := float(value)
	if is_nan(number) or is_inf(number) or number < minimum or number > maximum:
		return NAN
	if not allow_zero and number <= 0.0:
		return NAN
	return number