extends Node2D

@onready var race_manager: Node = $RaceManager
@onready var hud_label: Label = $HUD/HUDLabel

var _finished: bool = false


func _ready() -> void:
	race_manager.race_finished.connect(_on_race_finished)


func _process(_delta: float) -> void:
	var elapsed: float = race_manager.race_time
	var minutes := int(elapsed / 60.0)
	var seconds := fmod(elapsed, 60.0)
	var shown_lap: int = mini(race_manager.lap_count + 1, race_manager.laps_to_finish)
	if _finished:
		hud_label.text = "FINISH  ·  %02d:%04.1f  ·  R to reset" % [minutes, seconds]
	else:
		hud_label.text = "LAP %d/%d   ·   %02d:%04.1f   ·   BOOST %.0f%%" % [
			shown_lap,
			race_manager.laps_to_finish,
			minutes,
			seconds,
			_get_boost_amount(),
		]


func _get_boost_amount() -> float:
	var vehicle := get_tree().get_first_node_in_group("player_vehicle")
	return vehicle.get("boost_amount") if vehicle else 0.0


func _on_race_finished(_total_time: float) -> void:
	_finished = true
