extends Node2D

@onready var race_manager: Node = $RaceManager
@onready var hud_label: Label = $HUD/HUDLabel
@onready var boost_fill: Sprite2D = $HUD/RaceHUDArt/BoostBar/BoostFill
@onready var controls_label: Label = $HUD/ControlsLabel

const BOOST_FILL_SCALE := Vector2(0.52, 0.52)

var _finished: bool = false


func _ready() -> void:
	race_manager.race_finished.connect(_on_race_finished)
	boost_fill.z_index = 2
	if OS.is_debug_build():
		controls_label.text += "   ·   F3 telemetry"


func _process(_delta: float) -> void:
	var elapsed: float = race_manager.race_time
	var minutes := int(elapsed / 60.0)
	var seconds := fmod(elapsed, 60.0)
	var shown_lap: int = mini(race_manager.lap_count + 1, race_manager.laps_to_finish)
	_update_boost_bar()
	if _finished:
		hud_label.text = "FINISH  ·  %02d:%04.1f  ·  R to reset" % [minutes, seconds]
	else:
		hud_label.text = "LAP %d/%d   ·   %02d:%04.1f" % [
			shown_lap,
			race_manager.laps_to_finish,
			minutes,
			seconds,
		]


func _update_boost_bar() -> void:
	var vehicle := get_tree().get_first_node_in_group("player_vehicle")
	var ratio: float = 0.0
	if vehicle:
		var stats_resource := vehicle.get("stats") as Resource
		var capacity: float = float(stats_resource.get("boost_capacity")) if stats_resource else 1.0
		ratio = clampf(float(vehicle.get("boost_amount")) / maxf(capacity, 0.001), 0.0, 1.0)
	boost_fill.scale = Vector2(BOOST_FILL_SCALE.x * ratio, BOOST_FILL_SCALE.y)


func _on_race_finished(_total_time: float) -> void:
	_finished = true
