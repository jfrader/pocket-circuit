extends SceneTree
## Writes $PROMO_OUT/cars/car_NNN.png: procedurally generated cars at the game's
## native sprite size, cycling through every body type, for the car wall.

const GEN := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const CAR_COUNT := 104
const NATIVE_PIXEL_SCALE := 2
const RNG_SEED := 6102026
const SEED_MAX := 999999


func _initialize() -> void:
	var out_dir := OS.get_environment("PROMO_OUT").path_join("cars")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var types := GEN.available_types()
	var count := 0
	while count < CAR_COUNT:
		var payload := GEN.generate(rng.randi_range(1, SEED_MAX), types[count % types.size()], {})
		if not SPRITES.validate_payload(payload).is_empty():
			continue
		SPRITES.car_image(payload, NATIVE_PIXEL_SCALE).save_png(out_dir.path_join("car_%03d.png" % count))
		count += 1
	print("PROMO cars ", count)
	quit()
