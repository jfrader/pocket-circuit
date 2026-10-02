class_name CircuitRoutePreview
extends RefCounted

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const PREVIEW_SIZE := Vector2(420.0, 190.0)
const PREVIEW_MARGIN := 12.0


static func prepare(identity_value: Variant) -> Dictionary:
	var identity := IDENTITIES.normalize(identity_value)
	if identity.is_empty():
		return {}
	var seeds: Dictionary = identity["sub_seeds"]
	var prepared := TRACK_BUILDER.prepare_layout(
		StringName(identity["theme"]),
		StringName(identity["room"]),
		int(seeds["route"]),
		IDENTITIES.generation_options(identity)
	)
	if prepared.is_empty():
		return {}
	var points := _preview_points(prepared["centerline"], bool(identity["reverse"]))
	if points.is_empty():
		return {}
	var fingerprint := fingerprint_for_prepared(identity, prepared)
	return {
		"identity_fingerprint": String(identity["fingerprint"]),
		"loaded_fingerprint": fingerprint,
		"points": points,
		"display_name": String(identity["display_name"]),
		"summary": String(identity["summary"]),
		"story_id": String(prepared["spec"].get("story_id", "")),
		"obstacle_count": (prepared["spec"].get("obstacle_plan", []) as Array).size(),
	}


static func fingerprint_for_prepared(identity_value: Variant, prepared: Dictionary) -> String:
	var identity := IDENTITIES.normalize(identity_value)
	if identity.is_empty() or prepared.get("centerline") is not PackedVector2Array:
		return ""
	var centerline: PackedVector2Array = prepared["centerline"]
	var parts := PackedStringArray(["pc-loaded-preview-v1", String(identity["fingerprint"])])
	var step := maxi(1, centerline.size() / 64)
	var index := 0
	while index < centerline.size():
		var point := centerline[index]
		parts.append("%d,%d" % [roundi(point.x * 10.0), roundi(point.y * 10.0)])
		index += step
	var spec: Dictionary = prepared.get("spec", {})
	parts.append("story=%s" % String(spec.get("story_id", "")))
	parts.append("material=%d" % int(spec.get("material_seed", -1)))
	parts.append("dressing=%d" % int(spec.get("dressing_seed", -1)))
	parts.append("obstacle=%d" % int(spec.get("obstacle_seed", -1)))
	return "|".join(parts).sha256_text().substr(0, 16)


static func _preview_points(centerline: PackedVector2Array, reverse: bool) -> PackedVector2Array:
	if centerline.is_empty():
		return PackedVector2Array()
	var bounds := Rect2(centerline[0], Vector2.ZERO)
	for point: Vector2 in centerline:
		bounds = bounds.expand(point)
	if bounds.size.x < 0.001 or bounds.size.y < 0.001:
		return PackedVector2Array()
	var scale := minf(
		(PREVIEW_SIZE.x - PREVIEW_MARGIN * 2.0) / bounds.size.x,
		(PREVIEW_SIZE.y - PREVIEW_MARGIN * 2.0) / bounds.size.y
	)
	var offset := (PREVIEW_SIZE - bounds.size * scale) * 0.5 - bounds.position * scale
	var output := PackedVector2Array()
	var indices := range(centerline.size() - 1, -1, -4) if reverse else range(0, centerline.size(), 4)
	for index: int in indices:
		output.append(centerline[index] * scale + offset)
	return output