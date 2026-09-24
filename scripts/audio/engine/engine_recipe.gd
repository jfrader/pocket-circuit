class_name EngineRecipe
extends Resource

## Authored identity of one engine voice. Values are physical-ish abstractions:
## they feed the generator, never the per-sample path, and they never change at
## runtime. `from_vehicle` derives a deterministic default from VehicleStats so
## a car without a hand-authored recipe still gets a stable, distinct voice.

const GENERATOR_VERSION := 1
const MIN_CYLINDERS := 2
const MAX_CYLINDERS := 8
const MIN_GEARS := 2
const MAX_GEARS := 6

@export var recipe_id: String = ""
@export var generator_version: int = GENERATOR_VERSION
@export var identity_seed: String = ""
@export_range(2, 8) var cylinder_count: int = 3
@export var firing_order: PackedInt32Array = PackedInt32Array([0, 2, 1])
@export var displacement_l: float = 0.65
@export_range(0.0, 1.0) var cam: float = 0.48
@export var exhaust_primary_m: float = 0.41
@export_range(0.0, 1.0) var exhaust_body: float = 0.41
@export_enum("natural", "turbo") var aspiration: String = "turbo"
@export_range(0.0, 1.0) var turbo: float = 0.24
@export var idle_rpm: float = 1020.0
@export var redline_rpm: float = 7100.0
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array([3.32, 2.30, 1.61, 1.13])
@export var final_drive: float = 4.24
@export var output_trim_db: float = 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if recipe_id.is_empty():
		errors.append("recipe_id must not be empty")
	if identity_seed.is_empty():
		errors.append("identity_seed must not be empty")
	if generator_version < 1:
		errors.append("generator_version must be >= 1; got %d" % generator_version)
	if cylinder_count < MIN_CYLINDERS or cylinder_count > MAX_CYLINDERS:
		errors.append("cylinder_count must be %d..%d; got %d" % [MIN_CYLINDERS, MAX_CYLINDERS, cylinder_count])
	errors.append_array(_firing_order_errors())
	if not is_finite(displacement_l) or displacement_l <= 0.0:
		errors.append("displacement_l must be > 0; got %s" % str(displacement_l))
	if not is_finite(exhaust_primary_m) or exhaust_primary_m <= 0.0:
		errors.append("exhaust_primary_m must be > 0; got %s" % str(exhaust_primary_m))
	for property_name: String in ["cam", "exhaust_body", "turbo"]:
		var value := float(get(property_name))
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("%s must be within 0..1; got %s" % [property_name, str(value)])
	if not is_finite(idle_rpm) or idle_rpm <= 0.0:
		errors.append("idle_rpm must be > 0; got %s" % str(idle_rpm))
	if not is_finite(redline_rpm) or redline_rpm <= idle_rpm:
		errors.append("redline_rpm must be greater than idle_rpm; got %s and %s" % [str(redline_rpm), str(idle_rpm)])
	if aspiration != "natural" and aspiration != "turbo":
		errors.append("aspiration must be natural or turbo; got %s" % aspiration)
	errors.append_array(_gear_errors())
	if not is_finite(final_drive) or final_drive <= 0.0:
		errors.append("final_drive must be > 0; got %s" % str(final_drive))
	if not is_finite(output_trim_db) or absf(output_trim_db) > 24.0:
		errors.append("output_trim_db must be within -24..24; got %s" % str(output_trim_db))
	return errors


func is_valid() -> bool:
	return validate().is_empty()


## Stable key for caching a generated voice. It covers every value the generator
## reads, so a material retune invalidates the cache and a cosmetic change does not.
func signature() -> String:
	var parts := PackedStringArray()
	parts.append("v%d" % generator_version)
	parts.append(recipe_id)
	parts.append(identity_seed)
	parts.append("c%d" % cylinder_count)
	var order := PackedStringArray()
	for slot in firing_order:
		order.append(str(slot))
	parts.append("f%s" % ",".join(order))
	parts.append("d%.4f" % displacement_l)
	parts.append("m%.4f" % cam)
	parts.append("p%.4f" % exhaust_primary_m)
	parts.append("b%.4f" % exhaust_body)
	parts.append("t%.4f" % turbo)
	parts.append("i%.1f" % idle_rpm)
	parts.append("r%.1f" % redline_rpm)
	var gears := PackedStringArray()
	for ratio in gear_ratios:
		gears.append("%.3f" % ratio)
	parts.append("g%s" % ",".join(gears))
	parts.append("fd%.3f" % final_drive)
	return "|".join(parts)


## Deterministic default voice for a vehicle without a hand-authored recipe.
## Only semantically related stats move the voice; grip, steering, brakes and
## cosmetics never do, so a handling patch cannot silently replace a car's sound.
static func from_vehicle(vehicle_id: String, stats: VehicleStats) -> EngineRecipe:
	var recipe := EngineRecipe.new()
	recipe.recipe_id = vehicle_id
	recipe.identity_seed = vehicle_id
	if stats == null:
		return recipe
	var force_ratio := clampf(inverse_lerp(680.0, 1300.0, stats.engine_force), 0.0, 1.0)
	var speed_ratio := clampf(inverse_lerp(650.0, 750.0, stats.max_speed), 0.0, 1.0)
	var falloff_ratio := clampf(inverse_lerp(1.25, 2.25, stats.torque_falloff_exponent), 0.0, 1.0)
	var mass_ratio := clampf(inverse_lerp(0.65, 1.30, stats.mass), 0.0, 1.0)
	var boost_ratio := clampf(inverse_lerp(450.0, 700.0, stats.boost_power), 0.0, 1.0)
	recipe.cylinder_count = 2 + int(round(force_ratio * 2.0))
	recipe.firing_order = default_firing_order(recipe.cylinder_count)
	recipe.displacement_l = lerpf(0.48, 1.05, force_ratio)
	recipe.cam = lerpf(0.30, 0.75, falloff_ratio)
	recipe.exhaust_primary_m = maxf(0.20, 0.42 + 0.12 * force_ratio - 0.035 * float(recipe.cylinder_count - 2))
	recipe.exhaust_body = lerpf(0.30, 0.62, mass_ratio)
	recipe.turbo = lerpf(0.0, 0.55, boost_ratio)
	recipe.aspiration = "turbo" if recipe.turbo >= 0.12 else "natural"
	recipe.idle_rpm = 980.0 + 40.0 * float(recipe.cylinder_count - 2)
	recipe.redline_rpm = lerpf(6300.0, 8500.0, falloff_ratio)
	var first_gear := lerpf(3.60, 2.90, speed_ratio)
	recipe.gear_ratios = geometric_gears(first_gear, 1.13, 4)
	recipe.final_drive = lerpf(4.60, 3.70, speed_ratio)
	recipe.output_trim_db = 0.0
	return recipe


## Even firing order: cylinders fire in sequence, which is what a straight or
## even V engine does. Authored recipes override this for uneven orders.
static func default_firing_order(cylinder_count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	for cylinder in maxi(cylinder_count, MIN_CYLINDERS):
		order.append(cylinder)
	return order


static func geometric_gears(first: float, last: float, count: int) -> PackedFloat32Array:
	var ratios := PackedFloat32Array()
	var gears := clampi(count, MIN_GEARS, MAX_GEARS)
	if gears == 1:
		ratios.append(last)
		return ratios
	for index in gears:
		var t := float(index) / float(gears - 1)
		ratios.append(first * pow(last / first, t))
	return ratios


func _firing_order_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if firing_order.size() != cylinder_count:
		errors.append("firing_order must hold %d entries; got %d" % [cylinder_count, firing_order.size()])
		return errors
	var seen := {}
	for slot in firing_order:
		if slot < 0 or slot >= cylinder_count:
			errors.append("firing_order entry %d is outside 0..%d" % [slot, cylinder_count - 1])
		elif seen.has(slot):
			errors.append("firing_order repeats cylinder %d" % slot)
		seen[slot] = true
	return errors


func _gear_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if gear_ratios.size() < MIN_GEARS or gear_ratios.size() > MAX_GEARS:
		errors.append("gear_ratios must hold %d..%d ratios; got %d" % [MIN_GEARS, MAX_GEARS, gear_ratios.size()])
		return errors
	for index in gear_ratios.size():
		var ratio := gear_ratios[index]
		if not is_finite(ratio) or ratio <= 0.0:
			errors.append("gear_ratios[%d] must be > 0; got %s" % [index, str(ratio)])
			continue
		if index > 0 and ratio >= gear_ratios[index - 1]:
			errors.append("gear_ratios must decrease; gear %d is %s after %s" % [index, str(ratio), str(gear_ratios[index - 1])])
	return errors
