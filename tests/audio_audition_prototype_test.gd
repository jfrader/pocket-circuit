extends SceneTree

const CANDIDATE_MANIFEST := preload("res://prototypes/audio_audition/candidate_manifest.gd")
const EXPECTED_GROUPS := [
	&"engine_loop",
	&"countdown",
	&"go",
	&"ui_move",
	&"ui_confirm",
	&"drift",
	&"boost",
	&"impact",
	&"hazard_warning",
]
const REQUIRED_CANDIDATE_FIELDS := [
	"variant",
	"label",
	"path",
	"pack_name",
	"pack_filename",
	"pack_sha256",
	"source_page",
	"source_files",
	"transformation",
	"expected_duration_seconds",
	"loop",
]
const EXPECTED_SAMPLE_RATE := 48000

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var groups: Dictionary = CANDIDATE_MANIFEST.GROUPS
	var group_order: Array = CANDIDATE_MANIFEST.GROUP_ORDER
	_check(group_order == EXPECTED_GROUPS, "group order must cover the nine production seams exactly")
	_check(groups.size() == 9, "manifest must contain exactly 9 groups")

	var seen_paths := {}
	var candidate_count := 0
	for group_name: StringName in EXPECTED_GROUPS:
		if not groups.has(group_name):
			_failures.append("missing group %s" % group_name)
			continue
		var group: Dictionary = groups[group_name]
		_check(_non_empty_string(group.get("display_name")), "%s display_name must be complete" % group_name)
		_check(_non_empty_string(group.get("prompt")), "%s prompt must be complete" % group_name)
		_check(group.has("one_shot_cap_seconds"), "%s duration cap metadata is missing" % group_name)
		var candidates: Array = group.get("candidates", [])
		_check(candidates.size() >= 1 and candidates.size() <= 2, "%s must contain 1-2 candidates" % group_name)
		for candidate_index in candidates.size():
			candidate_count += 1
			_validate_candidate(group_name, group, candidates[candidate_index], candidate_index, seen_paths)

	if _failures.is_empty():
		print("AUDIO_AUDITION_PROTOTYPE_TEST PASS groups=9 candidates=%d sample_rate=48000Hz" % candidate_count)
		quit(0)
		return
	for failure: String in _failures:
		push_error("AUDIO_AUDITION_PROTOTYPE_TEST FAIL: " + failure)
	quit(1)


func _validate_candidate(
	group_name: StringName,
	group: Dictionary,
	candidate: Dictionary,
	candidate_index: int,
	seen_paths: Dictionary,
) -> void:
	var context := "%s candidate %d" % [group_name, candidate_index + 1]
	for field: String in REQUIRED_CANDIDATE_FIELDS:
		_check(candidate.has(field), "%s is missing metadata field %s" % [context, field])
	if REQUIRED_CANDIDATE_FIELDS.any(func(field: String) -> bool: return not candidate.has(field)):
		return

	for field: String in ["variant", "label", "path", "pack_name", "pack_filename", "pack_sha256", "source_page", "transformation"]:
		_check(_non_empty_string(candidate[field]), "%s field %s must be non-empty" % [context, field])
	var source_files: Array = candidate["source_files"]
	_check(not source_files.is_empty(), "%s must name at least one source file" % context)
	for source_file: Variant in source_files:
		_check(_non_empty_string(source_file), "%s contains an empty source filename" % context)

	var path: String = candidate["path"]
	_check(path.begins_with("res://prototypes/audio_audition/candidates/"), "%s must stay inside the prototype candidate directory" % context)
	_check(not path.contains("assets/audio"), "%s must not reference production assets/audio" % context)
	_check(path.get_extension().to_lower() == "ogg", "%s must be an OGG candidate" % context)
	_check(not seen_paths.has(path), "%s path must be unique: %s" % [context, path])
	seen_paths[path] = true
	_check(FileAccess.file_exists(path), "%s file is missing: %s" % [context, path])
	if not FileAccess.file_exists(path):
		return
	_check(not FileAccess.get_file_as_bytes(path).is_empty(), "%s file is empty: %s" % [context, path])

	var stream := load(path) as AudioStreamOggVorbis
	_check(stream != null, "%s must load through Godot as AudioStreamOggVorbis" % context)
	if stream == null:
		return
	_check(stream.get_length() > 0.0, "%s decoded duration must be positive" % context)
	var packet_sequence := stream.get_packet_sequence()
	if packet_sequence != null:
		_check(roundi(packet_sequence.get_sampling_rate()) == EXPECTED_SAMPLE_RATE, "%s sample rate must be 48 kHz" % context)

	var should_loop := group_name == &"engine_loop"
	_check(bool(candidate["loop"]) == should_loop, "%s loop flag must be true only for engine_loop" % context)
	if not should_loop:
		var duration_cap := float(group["one_shot_cap_seconds"])
		_check(duration_cap > 0.0, "%s one-shot duration cap must be positive" % group_name)
		_check(stream.get_length() <= duration_cap + 0.001, "%s duration %.3f exceeds %.3f second cap" % [context, stream.get_length(), duration_cap])
	var expected_duration := float(candidate["expected_duration_seconds"])
	_check(expected_duration > 0.0, "%s expected duration metadata must be positive" % context)
	_check(absf(stream.get_length() - expected_duration) <= 0.012, "%s decoded duration does not match manifest metadata" % context)


func _non_empty_string(value: Variant) -> bool:
	return value is String and not (value as String).strip_edges().is_empty()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
