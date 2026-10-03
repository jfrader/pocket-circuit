extends Node2D

const DRIFT_DUST := preload("res://assets/vfx/drift_dust.png")
const BOOST_FLAME := preload("res://assets/vfx/boost_flame_trail.png")
const IMPACT_FLASH := preload("res://assets/vfx/impact_flash.png")
const SKID_MARK := preload("res://assets/vfx/skid_mark.png")
const MAX_SKID_MARKS := 24
const SKID_INTERVAL := 0.11
const IMPACT_DURATION := 0.18
const IMPACT_AUDIO_COOLDOWN := 0.14

var _vehicle: RigidBody2D
var _tyre_state: Dictionary = {}
var _visual_root: Node2D
var _visual_base_scale := Vector2.ONE
var _dust_left: Sprite2D
var _dust_right: Sprite2D
var _boost_flame: Sprite2D
var _impact_flash: Sprite2D
var _animation_time: float = 0.0
var _skid_cooldown: float = 0.0
var _impact_time: float = 0.0
var _impact_audio_cooldown: float = 0.0
var _skid_marks: Array[Sprite2D] = []
var _was_boosting := false
var _app: Node


func _ready() -> void:
	_vehicle = get_parent() as RigidBody2D
	_app = get_node_or_null("/root/App")
	_visual_root = _vehicle.get_node("VisualRoot") as Node2D
	_visual_base_scale = _visual_root.scale
	_dust_left = _make_effect(DRIFT_DUST, 4, Vector2(-14.0, 24.0), Vector2(0.42, 0.42), -2)
	_dust_right = _make_effect(DRIFT_DUST, 4, Vector2(14.0, 24.0), Vector2(0.42, 0.42), -2)
	_dust_right.flip_h = true
	_boost_flame = _make_effect(BOOST_FLAME, 4, Vector2(0.0, 32.0), Vector2(0.48, 0.48), -1)
	_boost_flame.rotation = PI * 0.5
	_impact_flash = _make_effect(IMPACT_FLASH, 3, Vector2.ZERO, Vector2(1.0, 1.0), 3)
	_vehicle.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_animation_time += delta
	_skid_cooldown = maxf(0.0, _skid_cooldown - delta)
	_impact_audio_cooldown = maxf(0.0, _impact_audio_cooldown - delta)
	_vehicle.call("write_tyre_state", _tyre_state)
	var drifting := bool(_tyre_state["sliding"])
	var boosting := bool(_vehicle.call("is_boost_active"))
	# Boost is an event, so it fires once here. Drift is a sustained state and is
	# voiced continuously by AudioDirector from the same tyre state used here.
	if _vehicle.is_in_group("player_vehicle") and boosting and not _was_boosting:
		_play_sfx(&"boost", 0.82)
	_was_boosting = boosting
	_update_looping_effects(drifting, boosting)
	if drifting and _skid_cooldown <= 0.0:
		_spawn_skid_mark()
		_skid_cooldown = SKID_INTERVAL
	_update_impact(delta)
	_prune_skid_marks()


func _make_effect(texture: Texture2D, frames: int, local_position: Vector2, effect_scale: Vector2, effect_z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = frames
	sprite.position = local_position
	sprite.scale = effect_scale
	sprite.z_index = effect_z
	sprite.visible = false
	add_child(sprite)
	return sprite


func _update_looping_effects(drifting: bool, boosting: bool) -> void:
	var dust_frame := int(floor(_animation_time * 14.0)) % 4
	_dust_left.visible = drifting
	_dust_right.visible = drifting
	_dust_left.frame = dust_frame
	_dust_right.frame = (dust_frame + 2) % 4
	_boost_flame.visible = boosting
	_boost_flame.frame = int(floor(_animation_time * 18.0)) % 4


func _spawn_skid_mark() -> void:
	var mark := Sprite2D.new()
	mark.texture = SKID_MARK
	mark.global_position = _vehicle.global_position + Vector2.DOWN.rotated(_vehicle.rotation) * 18.0
	mark.global_rotation = _vehicle.rotation + PI * 0.5
	mark.scale = Vector2(0.22, 0.22)
	mark.modulate = Color(0.15, 0.14, 0.13, 0.3)
	mark.z_index = -1
	get_tree().current_scene.add_child(mark)
	_skid_marks.append(mark)
	var fade := mark.create_tween()
	fade.tween_property(mark, "modulate:a", 0.0, 2.2)
	fade.tween_callback(mark.queue_free)
	if _skid_marks.size() > MAX_SKID_MARKS:
		var oldest: Sprite2D = _skid_marks.pop_front() as Sprite2D
		if is_instance_valid(oldest):
			oldest.queue_free()


func _prune_skid_marks() -> void:
	for index in range(_skid_marks.size() - 1, -1, -1):
		if not is_instance_valid(_skid_marks[index]):
			_skid_marks.remove_at(index)


func _on_body_entered(_body: Node) -> void:
	_impact_time = IMPACT_DURATION
	_impact_flash.visible = true
	_impact_flash.frame = 0
	var camera := get_viewport().get_camera_2d()
	if _vehicle.is_in_group("player_vehicle") and camera and camera.has_method("add_impact_nudge"):
		camera.call("add_impact_nudge", clampf(_vehicle.linear_velocity.length() / 680.0, 0.25, 1.0))
	if _vehicle.is_in_group("player_vehicle") and _impact_audio_cooldown <= 0.0:
		var impact_strength := clampf((_vehicle.linear_velocity.length() - 45.0) / 480.0, 0.18, 0.9)
		_play_sfx(&"impact", impact_strength)
		_impact_audio_cooldown = IMPACT_AUDIO_COOLDOWN


func _update_impact(delta: float) -> void:
	if _impact_time <= 0.0:
		_impact_flash.visible = false
		_visual_root.scale = _visual_root.scale.lerp(_visual_base_scale, minf(1.0, delta * 18.0))
		return
	_impact_time = maxf(0.0, _impact_time - delta)
	var progress := 1.0 - (_impact_time / IMPACT_DURATION)
	_impact_flash.frame = mini(2, int(progress * 3.0))
	var squash := sin(progress * PI)
	_visual_root.scale = _visual_base_scale * Vector2(1.0 + squash * 0.035, 1.0 - squash * 0.035)


func _play_sfx(sound_name: StringName, volume_scale: float) -> void:
	if is_instance_valid(_app) and _app.has_method("play_sfx"):
		_app.call("play_sfx", sound_name, volume_scale)
