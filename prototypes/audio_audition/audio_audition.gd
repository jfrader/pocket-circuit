extends SceneTree

const CANDIDATE_MANIFEST := preload("res://prototypes/audio_audition/candidate_manifest.gd")

const MIDNIGHT := Color("080b12")
const PANEL := Color("0d121d")
const RULE := Color("263044")
const TEXT := Color("e7ebf2")
const MUTED := Color("7d899d")
const ACCENT := Color("ef9d4d")
const COOL := Color("63d7d1")


class WorkbenchBackdrop:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), MIDNIGHT)
		draw_rect(Rect2(0.0, 0.0, size.x, 8.0), ACCENT)
		draw_rect(Rect2(42.0, 96.0, 2.0, size.y - 154.0), RULE)
		draw_line(Vector2(42.0, size.y - 80.0), Vector2(size.x - 42.0, size.y - 80.0), RULE, 1.0)
		for index in 12:
			var x := 58.0 + float(index) * 19.0
			var height := 6.0 + float((index * 7) % 17)
			draw_rect(Rect2(x, size.y - 111.0 - height, 3.0, height), Color(0.31, 0.72, 0.70, 0.34))


class AuditionInterface:
	extends Control

	var _groups: Dictionary
	var _group_order: Array
	var _group_index := 0
	var _candidate_index := 0
	var _player: AudioStreamPlayer
	var _group_rail: Label
	var _cue_name: Label
	var _variant: Label
	var _candidate_name: Label
	var _source: Label
	var _technical: Label
	var _prompt: Label
	var _status: Label


	func _init(groups: Dictionary, group_order: Array) -> void:
		_groups = groups
		_group_order = group_order


	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process_unhandled_key_input(true)
		_build_interface()
		_refresh_selection()


	func _unhandled_key_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo:
			return
		match event.keycode:
			KEY_LEFT:
				_change_candidate(-1)
			KEY_RIGHT:
				_change_candidate(1)
			KEY_UP:
				_change_group(-1)
			KEY_DOWN:
				_change_group(1)
			KEY_SPACE:
				_toggle_playback()
			KEY_R:
				_play_selected(true)
			KEY_ESCAPE:
				_player.stop()
				get_tree().quit(0)
			_:
				return
		get_viewport().set_input_as_handled()


	func _build_interface() -> void:
		var backdrop := WorkbenchBackdrop.new()
		add_child(backdrop)

		_player = AudioStreamPlayer.new()
		_player.name = "AuditionPlayer"
		_player.finished.connect(_on_playback_finished)
		add_child(_player)

		var page := VBoxContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.offset_left = 64.0
		page.offset_top = 38.0
		page.offset_right = -64.0
		page.offset_bottom = -32.0
		page.add_theme_constant_override("separation", 8)
		add_child(page)

		var prototype_mark := _make_label("PROTOTYPE / NOT SHIP AUDIO", 14, ACCENT)
		prototype_mark.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		page.add_child(prototype_mark)

		var title := _make_label("MIDNIGHT AUDIO WORKBENCH", 30, TEXT)
		page.add_child(title)

		var subtitle := _make_label("Nine current production seams · compact CC0 A/B pass", 15, MUTED)
		page.add_child(subtitle)

		var top_gap := Control.new()
		top_gap.custom_minimum_size.y = 30.0
		page.add_child(top_gap)

		var body := HBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 46)
		page.add_child(body)

		var rail := VBoxContainer.new()
		rail.custom_minimum_size.x = 254.0
		rail.add_theme_constant_override("separation", 16)
		body.add_child(rail)

		var rail_heading := _make_label("CUE INDEX  /  ↑ ↓", 12, MUTED)
		rail.add_child(rail_heading)
		_group_rail = _make_label("", 16, MUTED)
		_group_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_group_rail.add_theme_constant_override("line_spacing", 9)
		rail.add_child(_group_rail)

		var divider := ColorRect.new()
		divider.color = RULE
		divider.custom_minimum_size.x = 1.0
		body.add_child(divider)

		var detail := VBoxContainer.new()
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_theme_constant_override("separation", 10)
		body.add_child(detail)

		_cue_name = _make_label("", 13, COOL)
		detail.add_child(_cue_name)

		var selector := HBoxContainer.new()
		selector.add_theme_constant_override("separation", 20)
		detail.add_child(selector)
		_variant = _make_label("A", 72, ACCENT)
		_variant.custom_minimum_size.x = 76.0
		selector.add_child(_variant)
		var variant_stack := VBoxContainer.new()
		variant_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.add_child(variant_stack)
		var variant_hint := _make_label("CANDIDATE  /  ← →", 12, MUTED)
		variant_stack.add_child(variant_hint)
		_candidate_name = _make_label("", 28, TEXT)
		variant_stack.add_child(_candidate_name)

		var detail_rule := ColorRect.new()
		detail_rule.color = RULE
		detail_rule.custom_minimum_size.y = 1.0
		detail.add_child(detail_rule)

		_source = _make_label("", 14, MUTED)
		_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(_source)
		_technical = _make_label("", 14, TEXT)
		detail.add_child(_technical)

		var prompt_heading := _make_label("AUDITION QUESTION", 12, ACCENT)
		detail.add_child(prompt_heading)
		_prompt = _make_label("", 19, TEXT)
		_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_prompt.custom_minimum_size.y = 72.0
		detail.add_child(_prompt)

		_status = _make_label("READY · explicit playback only", 13, COOL)
		detail.add_child(_status)

		var controls := _make_label("SPACE PLAY/STOP   R REPLAY   ←/→ A/B   ↑/↓ CUE   ESC QUIT", 13, MUTED)
		controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		page.add_child(controls)


	func _make_label(label_text: String, font_size: int, color: Color) -> Label:
		var label := Label.new()
		label.text = label_text
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		return label


	func _change_group(delta: int) -> void:
		_stop_for_selection_change()
		_group_index = wrapi(_group_index + delta, 0, _group_order.size())
		_candidate_index = 0
		_refresh_selection()


	func _change_candidate(delta: int) -> void:
		_stop_for_selection_change()
		var candidates: Array = _current_group()["candidates"]
		_candidate_index = wrapi(_candidate_index + delta, 0, candidates.size())
		_refresh_selection()


	func _stop_for_selection_change() -> void:
		_player.stop()
		_player.stream = null
		_status.text = "READY · explicit playback only"


	func _refresh_selection() -> void:
		var group_name: StringName = _group_order[_group_index]
		var group := _current_group()
		var candidate := _current_candidate()
		var source_stream := load(candidate["path"]) as AudioStreamOggVorbis

		var rail_lines := PackedStringArray()
		for index in _group_order.size():
			var indexed_name: StringName = _group_order[index]
			var prefix := "▶" if index == _group_index else "·"
			rail_lines.append("%s  %02d  %s" % [prefix, index + 1, _groups[indexed_name]["display_name"]])
		_group_rail.text = "\n".join(rail_lines)
		_cue_name.text = "%02d / %02d    %s" % [_group_index + 1, _group_order.size(), String(group_name).to_upper()]
		_variant.text = candidate["variant"]
		_candidate_name.text = candidate["label"]
		_source.text = "SOURCE  %s  ·  %s" % [candidate["pack_name"], " + ".join(PackedStringArray(candidate["source_files"]))]
		var duration := source_stream.get_length() if source_stream != null else 0.0
		_technical.text = "%.3f s    /    48 kHz MONO    /    %s" % [duration, "LOOPED" if candidate["loop"] else "ONE-SHOT"]
		_prompt.text = group["prompt"]


	func _current_group() -> Dictionary:
		return _groups[_group_order[_group_index]]


	func _current_candidate() -> Dictionary:
		return _current_group()["candidates"][_candidate_index]


	func _toggle_playback() -> void:
		if _player.playing:
			_player.stop()
			_status.text = "STOPPED"
			return
		_play_selected(false)


	func _play_selected(is_replay: bool) -> void:
		var candidate := _current_candidate()
		var source_stream := load(candidate["path"]) as AudioStreamOggVorbis
		if source_stream == null:
			_status.text = "LOAD FAILED"
			return
		_player.stop()
		if candidate["loop"]:
			var looped_stream := source_stream.duplicate(true) as AudioStreamOggVorbis
			looped_stream.loop = true
			_player.stream = looped_stream
		else:
			_player.stream = source_stream
		_player.play()
		_status.text = "%s  ·  %s %s" % ["REPLAYING" if is_replay else "PLAYING", _group_order[_group_index], candidate["variant"]]


	func _on_playback_finished() -> void:
		_status.text = "FINISHED · SPACE to play again"


func _initialize() -> void:
	root.title = "Pocket Circuit — Audio Audition Prototype"
	root.size = Vector2i(1100, 720)
	root.content_scale_size = Vector2i(1100, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var interface := AuditionInterface.new(CANDIDATE_MANIFEST.GROUPS, CANDIDATE_MANIFEST.GROUP_ORDER)
	root.add_child(interface)
