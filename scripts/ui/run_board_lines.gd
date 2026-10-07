class_name RunBoardLines
extends Control

## Draws the run map's edges behind the node chips. Pure drawing: the board
## screen feeds it the segment list computed from the map's parent/child pairs.

var segments: Array[PackedVector2Array] = []
var line_color := Color(1.0, 0.94, 0.85, 0.38)
var line_width := 3.0


func _draw() -> void:
	for segment: PackedVector2Array in segments:
		if segment.size() >= 2:
			draw_polyline(segment, line_color, line_width, true)
