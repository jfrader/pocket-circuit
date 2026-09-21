extends SceneTree

const MUSIC_WAV_NAMES: Array[String] = ["menu_loop", "race_loop"]
const REVIEW_OGG_NAMES: Array[String] = [
	"engine_loop", "countdown", "go", "ui_move", "ui_confirm", "drift", "boost",
	"impact", "hazard_warning",
]


func _initialize() -> void:
	for sound_name: String in MUSIC_WAV_NAMES:
		var path := "res://assets/audio/%s.wav" % sound_name
		var stream := load(path) as AudioStreamWAV
		if stream == null or stream.data.is_empty() or stream.mix_rate != 22050:
			_fail("%s should load as non-empty 22.05 kHz PCM" % path)
			return
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
