extends RefCounted
## Transient tyre coating. Contacts of the same material share one layer;
## different materials build/decay independently. The highest contribution owns
## the applied profile; equal contributions use material name order, never entry order.
const MIN_GRIP := 0.2
const MAX_STEERING_NOISE := 0.25
const WANDER_FREQUENCIES := Vector2(2.3, 4.1)
const WANDER_BLEND := 0.65
const SECONDARY_PHASE_SCALE := 1.7

var layers: Dictionary = {}
var amount := 0.0
var grip_multiplier := 1.0
var steering_noise := 0.0
var color := Color.WHITE
var _contacts: Dictionary = {}
var _elapsed := 0.0
var _phase := 0.0


func set_seed(value: int) -> void:
	_phase = float(posmod(value, 65536)) / 65536.0 * TAU
	_elapsed = 0.0


func enter(source: int, material: StringName, profile: Dictionary) -> void:
	leave(source)
	if profile.is_empty() or float(profile.get("build_rate", 0.0)) <= 0.0:
		return
	_contacts[source] = material
	if not layers.has(material):
		layers[material] = {"amount": 0.0, "profile": profile.duplicate(true)}


func leave(source: int) -> void:
	_contacts.erase(source)


func step(delta: float) -> void:
	_elapsed += delta
	amount = 0.0
	grip_multiplier = 1.0
	steering_noise = 0.0
	color = Color.WHITE
	var noise_strength := 0.0
	var touching_materials := _contacts.values()
	var materials := layers.keys()
	materials.sort()
	for material: StringName in materials:
		var layer: Dictionary = layers[material]
		var profile: Dictionary = layer["profile"]
		var touching := touching_materials.has(material)
		var rate := float(profile["build_rate"] if touching else profile["decay_rate"])
		var weight := move_toward(float(layer["amount"]), 1.0 if touching else 0.0, maxf(rate, 0.0) * delta)
		layer["amount"] = weight
		if weight <= 0.0 and not touching:
			layers.erase(material)
			continue
		if weight > amount:
			amount = weight
			color = profile["color"]
			grip_multiplier = 1.0 - float(profile["grip_penalty"]) * weight
			noise_strength = float(profile["steering_noise"]) * weight
	grip_multiplier = clampf(grip_multiplier, MIN_GRIP, 1.0)
	# Two smooth waves, never per-frame randomness or a shared RNG stream.
	steering_noise = minf(noise_strength, MAX_STEERING_NOISE) * lerpf(
		sin(_elapsed * WANDER_FREQUENCIES.y + _phase * SECONDARY_PHASE_SCALE),
		sin(_elapsed * WANDER_FREQUENCIES.x + _phase), WANDER_BLEND,
	)


func reset() -> void:
	layers.clear()
	_contacts.clear()
	_elapsed = 0.0
	amount = 0.0
	grip_multiplier = 1.0
	steering_noise = 0.0
	color = Color.WHITE
