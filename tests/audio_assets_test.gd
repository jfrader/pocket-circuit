extends SceneTree

const AUDIO_NAMES: Array[String] = [
	"menu_loop", "race_loop", "engine_loop", "countdown", "go", "ui_move",
	"ui_confirm", "drift", "boost", "impact", "hazard_warning",
]
func _initialize() -> void:
	for sound_name: String in AUDIO_NAMES:
		var path := "res://assets/audio/%s.wav" % sound_name
		if not FileAccess.file_exists(path):
			_fail("missing audio asset %s" % path)
			return
		var stream := load(path) as AudioStreamWAV
		if stream == null or stream.data.is_empty() or stream.mix_rate != 22050:
			_fail("%s should load as non-empty 22.05 kHz PCM" % path)
			return
	print("AUDIO_ASSETS_TEST PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("AUDIO_ASSETS_TEST FAIL: " + message)
	quit(1)
