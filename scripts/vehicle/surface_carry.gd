extends RefCounted
## Transient tyre coating. Contacts of the same material share one layer;
## different materials build/decay independently, independent of entry order.

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
	for material: StringName in layers.keys():
		var layer: Dictionary = layers[material]
		var profile: Dictionary = layer["profile"]
		var touching := touching_materials.has(material)
		var rate := float(profile["build_rate"] if touching else profile["decay_rate"])
		var weight := move_toward(float(layer["amount"]), 1.0 if touching else 0.0, maxf(rate, 0.0) * delta)
		layer["amount"] = weight
		if weight <= 0.0 and not touching:
			layers.erase(material)
			continue
		grip_multiplier -= float(profile["grip_penalty"]) * weight
		noise_strength += float(profile["steering_noise"]) * weight
		if weight > amount:
			amount = weight
			color = profile["color"]
	grip_multiplier = clampf(grip_multiplier, 0.2, 1.0)
	# Two smooth waves, never per-frame randomness or a shared RNG stream.
	steering_noise = minf(noise_strength, 0.25) * (sin(_elapsed * 2.3 + _phase) * 0.65 + sin(_elapsed * 4.1 + _phase * 1.7) * 0.35)


func reset() -> void:
	layers.clear()
	_contacts.clear()
	_elapsed = 0.0
	amount = 0.0
	grip_multiplier = 1.0
	steering_noise = 0.0
	color = Color.WHITE
