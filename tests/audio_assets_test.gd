extends SceneTree

const REVIEW_OGG_NAMES: Array[String] = [
	"engine_loop", "countdown", "go", "ui_move", "ui_confirm", "drift", "boost",
	"impact", "hazard_warning",
]


func _initialize() -> void:
	for sound_name: String in REVIEW_OGG_NAMES:
		var path := "res://assets/audio/%s.ogg" % sound_name
		var stream := load(path) as AudioStreamOggVorbis
		if stream == null or stream.get_length() <= 0.0:
			_fail("%s should load as non-empty OGG audio" % path)
			return
	print("AUDIO_ASSETS_TEST PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("AUDIO_ASSETS_TEST FAIL: " + message)
	quit(1)
