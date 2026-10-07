extends RefCounted

## Test support: plays a run through the App seams the way the board does.
## Race-type stops are started and reported at a finish position; the other
## stops take their first action.

const WIN := 1


static func settle(app: Object, session: RunSession, position: int = WIN) -> void:
	var node: Dictionary = session.current_node()
	var id := String(node.get("id", ""))
	match String(node.get("type", "")):
		"race", "act_rival":
			app.call("start_run_race", id)
			app.call("report_race_result", position, 1.0, [], false, {})
		"rival":
			app.call("start_run_rival", id)
			app.call("report_race_result", position, 1.0, [], false, {})
		"bench":
			app.call("run_bench_repair", session.current_car_id)
		"lockup":
			app.call("run_open_lockup")
		"errand":
			app.call("run_resolve_errand", 0)


## Moves along the run, racing every race-type stop it passes (and winning),
## until it stands on an unsettled stop of the wanted type. Prefers a wanted
## child when one is offered. Returns false if the run ends or the steps run
## out first.
static func walk_to(app: Object, session: RunSession, wanted: String, max_steps: int = 80) -> bool:
	for step: int in range(max_steps):
		if session.is_failed() or session.is_complete():
			return false
		if String(session.current_node().get("type", "")) == wanted and not session.resolved_nodes.has(session.current_node_id):
			return true
		if session.is_race_pending():
			settle(app, session)
			continue
		var options: Array[Dictionary] = session.available_nodes()
		if options.is_empty():
			return false
		var next := String(options[0]["id"])
		for option: Dictionary in options:
			if String(option["type"]) == wanted:
				next = String(option["id"])
				break
		if not bool(app.call("enter_run_node", next)):
			return false
	return false
