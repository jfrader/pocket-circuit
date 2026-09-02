extends RefCounted

const MAX_FORWARD_NUDGE_RATIO := 0.10
const MIN_HEADING_CAP_DEGREES := 2.0
const MAX_HEADING_CAP_DEGREES := 14.0
const ANGULAR_CONTACT_DAMPING_RATE := 12.0
const MIN_SEPARATION_SPEED := 36.0


static func resolve_contact(sample: Dictionary) -> Dictionary:
	var delta := maxf(float(sample.get("delta", 1.0 / 60.0)), 0.0001)
	var intended_forward := (sample.get("intended_forward", Vector2.UP) as Vector2).normalized()
	var right := Vector2(-intended_forward.y, intended_forward.x)
	var normal := (sample.get("normal", Vector2.UP) as Vector2).normalized()
	var relative_velocity := sample.get("relative_velocity", Vector2.ZERO) as Vector2
	var impulse := sample.get("impulse", Vector2.ZERO) as Vector2
	var previous_velocity := sample.get("previous_velocity", Vector2.ZERO) as Vector2
	var solver_velocity := sample.get("solver_velocity", previous_velocity) as Vector2
	var self_mass := maxf(float(sample.get("self_mass", 1.0)), 0.01)
	var other_mass := maxf(float(sample.get("other_mass", 1.0)), 0.01)
	var is_new_contact := bool(sample.get("is_new_contact", true))

	var closing_speed := maxf(0.0, -relative_velocity.dot(normal))
	var impulse_speed := impulse.length() / self_mass
	var directness := 0.0
	if relative_velocity.length_squared() > 0.001:
		directness = clampf(absf(relative_velocity.normalized().dot(normal)), 0.0, 1.0)
	var heading_alignment := absf(intended_forward.dot(normal))
	var mass_share := other_mass / (self_mass + other_mass)
	var severity := clampf(
		0.55 * closing_speed / 350.0
		+ 0.25 * impulse_speed / 280.0
		+ 0.20 * directness,
		0.0,
		1.0
	)
	var glancing_factor := 0.20 + 0.80 * directness
	var orientation_factor := 0.65 + 0.35 * heading_alignment
	var loss_ratio := severity * mass_share * 0.42 * glancing_factor * orientation_factor
	if closing_speed > 45.0:
		loss_ratio += 0.025 * clampf((closing_speed - 45.0) / 100.0, 0.0, 1.0)
	loss_ratio = clampf(loss_ratio, 0.0, 0.28)

	var previous_forward_speed := previous_velocity.dot(intended_forward)
	var previous_lateral_speed := previous_velocity.dot(right)
	var solver_forward_speed := solver_velocity.dot(intended_forward)
	var solver_lateral_speed := solver_velocity.dot(right)
	var rear_contact := intended_forward.dot(normal) > 0.55 and previous_forward_speed > 0.0
	var nudge_ratio := 0.0
	var forward_speed := solver_forward_speed
	var lateral_speed := solver_lateral_speed
	var heading_cap_degrees := lerpf(MIN_HEADING_CAP_DEGREES, MAX_HEADING_CAP_DEGREES, severity)
	if is_new_contact:
		if rear_contact:
			var nudge_cap_ratio := minf(MAX_FORWARD_NUDGE_RATIO, severity * mass_share * 0.12)
			var maximum_forward_speed := previous_forward_speed * (1.0 + nudge_cap_ratio)
			forward_speed = clampf(solver_forward_speed, previous_forward_speed, maximum_forward_speed)
			nudge_ratio = (forward_speed - previous_forward_speed) / maxf(previous_forward_speed, 0.001)
		elif solver_forward_speed * previous_forward_speed < 0.0:
			forward_speed = solver_forward_speed
		else:
			var loss_target_speed := previous_forward_speed * (1.0 - loss_ratio)
			forward_speed = clampf(
				solver_forward_speed,
				minf(previous_forward_speed, loss_target_speed),
				maxf(previous_forward_speed, loss_target_speed)
			)
		var impulse_weight := clampf(0.22 + impulse_speed / 500.0, 0.22, 0.62)
		lateral_speed = lerpf(previous_lateral_speed, solver_lateral_speed, impulse_weight)
		var lateral_limit := maxf(8.0 * severity, absf(forward_speed) * tan(deg_to_rad(heading_cap_degrees)))
		lateral_speed = clampf(lateral_speed, -lateral_limit, lateral_limit)

	var arcade_velocity := intended_forward * forward_speed + right * lateral_speed
	var velocity := arcade_velocity - normal * arcade_velocity.dot(normal) + normal * solver_velocity.dot(normal)
	if not rear_contact and absf(normal.dot(right)) > 0.45:
		var along_normal := velocity.dot(normal)
		if along_normal < MIN_SEPARATION_SPEED:
			velocity += normal * (MIN_SEPARATION_SPEED - along_normal)

	var angular_cap := deg_to_rad(lerpf(18.0, 105.0, severity))
	var resolved_angular_velocity := clampf(float(sample.get("solver_angular_velocity", 0.0)), -angular_cap, angular_cap)
	if is_new_contact:
		resolved_angular_velocity *= 0.55
	else:
		resolved_angular_velocity *= exp(-ANGULAR_CONTACT_DAMPING_RATE * delta)

	return {
		"velocity": velocity,
		"angular_velocity": resolved_angular_velocity,
		"closing_speed": closing_speed,
		"impulse_speed": impulse_speed,
		"mass_share": mass_share,
		"severity": severity,
		"loss_ratio": loss_ratio if not rear_contact else 0.0,
		"nudge_ratio": nudge_ratio,
		"heading_cap_degrees": heading_cap_degrees,
		"rear_contact": rear_contact,
		"is_new_contact": is_new_contact,
	}
