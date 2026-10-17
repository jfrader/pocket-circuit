extends SceneTree

const WALK := preload("res://tests/support/run_walk.gd")
const SCENE := preload("res://scripts/ui/run_errand_scene.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	var seen: Dictionary = {}
	var different_nodes := false
	for seed_value in range(900004, 900012):
		var session: RunSession = app.call("start_run", seed_value)
		if not WALK.walk_to(app, session, "errand"):
			continue
		var before := RunSession.serialize(session)
		shell.call("show_run_errand")
		await process_frame
		var requester := shell.find_child("ErrandRequester", true, false) as Label
		var task := shell.find_child("ErrandTask", true, false) as Label
		if not _expect(requester != null and task != null, "errand shows a requester and literal task above its choices"):
			return
		var roster_names: Array[String] = []
		var node_requests: Dictionary = {}
		for node_id: String in session.current_map.nodes:
			for driver: Dictionary in session.opponents_for_node(node_id).get("opponents", []):
				roster_names.append(String(driver["name"]).to_upper())
			if session.current_map.nodes[node_id]["type"] == "errand":
				var request := SCENE.request_for_node(session, node_id)
				node_requests[String(request["requester"]["id"]) + String(request["task"])] = true
		different_nodes = different_nodes or node_requests.size() > 1
		if not _expect(requester.text.trim_prefix("FROM: ") in roster_names and task.text in SCENE.TASKS, "requester belongs to this night's procedural cast and task is literal"):
			return
		var copy := requester.text + task.text
		seen[copy] = true
		var pay := shell.find_child("ErrandPay", true, false) as Button
		if not _expect(task.get_global_rect().end.y <= pay.get_global_rect().position.y and RunSession.serialize(session) == before, "story sits above choices without changing run state"):
			return
		shell.call("show_run_board")
		shell.call("show_run_errand")
		await process_frame
		if not _expect((shell.find_child("ErrandRequester", true, false) as Label).text + (shell.find_child("ErrandTask", true, false) as Label).text == copy, "reopening the same node preserves its request"):
			return
		var restored := RunSession.deserialize(before)
		if not _expect(SCENE.request_for_node(restored, restored.current_node_id) == SCENE.request_for_node(session, session.current_node_id), "save restoration preserves the request"):
			return
	if not _expect(seen.size() > 1, "different run seeds change the request"):
		return
	if not _expect(different_nodes, "different errand nodes have their own requests"):
		return
	app.call("start_run", 900004)
	shell.set("_run_intro_pending", false)
	shell.call("show_run_board")
	await process_frame
	var help := shell.find_child("ActionHelp", true, false) as Button
	if not _expect(help != null and help.text == "?", "run board offers a small controls action"):
		return
	help.pressed.emit()
	await process_frame
	var note := shell.find_child("RunIntro", true, false) as Control
	var intro := preload("res://scripts/ui/run_board_intro.gd")
	if not _expect(note != null and (note.get_node("RunIntroCopy") as Label).text == intro.COPY and note.mouse_filter == Control.MOUSE_FILTER_IGNORE, "help reopens the same nonblocking controls note"):
		return
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	note.call("_input", cancel)
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) == null and shell.get("_screen") == "run_board", "controls note dismisses without leaving the board"):
		return
	help.pressed.emit()
	await process_frame
	if not _expect(shell.find_child("RunIntro", true, false) != null, "controls note can be reopened repeatedly"):
		return
	print("RUN_ERRAND_STORY_TEST PASS requester=seeded_cast task=literal deterministic=node_and_seed help=reopen_nonblocking")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_ERRAND_STORY_TEST FAIL: " + message)
		quit(1)
	return condition
