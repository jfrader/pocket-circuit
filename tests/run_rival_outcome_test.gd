extends SceneTree

## GURI-1740f rival duel: `rival` node hands over via start_run_rival to the real
## race flow (1v1 rival_duel), report resolves via resolve_rival (win/loss), persist,
## route back to board, run not ended. Copy of idioms from run_race_outcome_test.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame

	# --- Win case (separate session, retry seeds for ~12% rival density) ---
	var find_win: Dictionary = _find_rival_before_enter(app, 30, 80)
	var win_sess: RunSession = find_win.get("sess") as RunSession
	var rival_id: String = String(find_win.get("rival_id", ""))
	if not _expect(win_sess != null and not rival_id.is_empty(), "a rival node must be found within bounded seed retries and walk"):
		return

	var owned_before: int = win_sess.owned_cars.size()
	if not _expect(bool(app.call("start_run_rival", rival_id)), "start_run_rival must accept an available rival node"):
		return
	if not _expect(String(win_sess.current_node_id) == rival_id, "the rival node must be entered"):
		return
	var race_session: Dictionary = app.get("current_race_session")
	if not _expect(String(race_session.get("mode", "")) == "run", "the race session must be a run duel"):
		return
	if not _expect(String(race_session.get("run_node_id", "")) == rival_id, "the race session must carry the run node"):
		return
	var ev: Dictionary = race_session.get("event", {}) as Dictionary
	if not _expect(String(ev.get("race_format", "")) == "rival_duel", "must use rival_duel format from championship path"):
		return
	if not _expect(int(ev.get("opponent_count", 0)) == 1, "duel must declare exactly 1 opponent"):
		return

	# Drive the real report seam for a win (pos 1 beats the single opponent).
	if not _expect(bool(app.call("report_race_result", 1, 30.0, [], false, {})), "reporting a win on rival duel must succeed"):
		return
	if not _expect(win_sess.owned_cars.size() == owned_before + 1, "a win must grant exactly one owned car (via resolve_rival)"):
		return
	if not _expect(not win_sess.failed, "a win on rival must not end the run"):
		return
	var after_win: Dictionary = app.get("current_race_session")
	if not _expect(String(after_win.get("post_race_destination", "")) == "run_board", "the rival duel win must route back to the board"):
		return

	# The save follows the resolved run (owned car persisted).
	var live_store: Object = app.get("_save_store")
	var path: String = String(live_store.get("save_path"))
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var saved_run: Dictionary = saved.get("current_run", {}) as Dictionary
	var saved_owned: Dictionary = saved_run.get("owned_cars", {}) as Dictionary
	if not _expect(saved_owned.size() == win_sess.owned_cars.size(), "the save must carry the granted rival car"):
		return

	# --- Loss case (separate session, fresh run, retry seeds) ---
	var find_loss: Dictionary = _find_rival_before_enter(app, 30, 80)
	var loss_sess: RunSession = find_loss.get("sess") as RunSession
	rival_id = String(find_loss.get("rival_id", ""))
	if not _expect(loss_sess != null and not rival_id.is_empty(), "a rival node must be found for loss within bounded retries"):
		return

	var budget_before: int = loss_sess.run_budget
	var wear_before: String = loss_sess.run_state.get_car_wear(loss_sess.current_car_id)
	if not _expect(bool(app.call("start_run_rival", rival_id)), "start_run_rival must accept for loss"):
		return
	if not _expect(bool(app.call("report_race_result", 2, 35.0, [], false, {})), "reporting a loss on rival duel must succeed"):
		return

	# Loss applies the session's documented penalty exactly once (from resolve_rival): budget cost, or wear if over.
	var budget_after: int = loss_sess.run_budget
	var wear_after: String = loss_sess.run_state.get_car_wear(loss_sess.current_car_id)
	var penalty_seen: bool = (budget_after < budget_before) or (wear_after != wear_before)
	if not _expect(penalty_seen, "loss must apply exactly the resolve_rival penalty (budget or wear)"):
		return
	if not _expect(not loss_sess.failed, "a loss on rival must not end the run (only overdraft crash can fail, 0.6 from clean does not)"):
		return
	var after_loss: Dictionary = app.get("current_race_session")
	if not _expect(String(after_loss.get("post_race_destination", "")) == "run_board", "the rival duel loss must route back to the board"):
		return

	# Save follows.
	saved = SAVE_STORE.new(path).load_data()
	saved_run = saved.get("current_run", {}) as Dictionary
	if not _expect(int(saved_run.get("run_budget", -1)) == loss_sess.run_budget, "the save must carry the loss budget state"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_RIVAL_OUTCOME_TEST PASS")
	quit(0)


## Tries up to max_seeds fresh start_run(seed) + bounded position-only walk until a rival
## is seen in available_nodes() but does not enter it (start_run_rival will). Returns {"sess": RunSession, "rival_id": String} or empty.
## Rivals ~12%, bounded retries per spec.
func _find_rival_before_enter(app: Object, max_seeds: int, walk_budget: int) -> Dictionary:
	for attempt in max_seeds:
		var seed: int = 1740010 + attempt * 17
		var sess: RunSession = app.call("start_run", seed) as RunSession
		if sess == null:
			continue
		var steps: int = 0
		while steps < walk_budget:
			steps += 1
			var options: Array[Dictionary] = sess.available_nodes()
			if options.is_empty():
				break
			for entry: Dictionary in options:
				var nid: String = String(entry.get("id", ""))
				var node: Dictionary = sess.current_map.get_node(nid) as Dictionary
				if String(node.get("type", "")) == "rival":
					return {"sess": sess, "rival_id": nid}
			# advance using app seam to keep position-only like other tests
			var first_id: String = ""
			if options.size() > 0:
				first_id = String(options[0].get("id", ""))
			if first_id.is_empty() or not bool(app.call("enter_run_node", first_id)):
				break
	return {"sess": null, "rival_id": ""}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_RIVAL_OUTCOME_TEST FAIL: " + message)
	quit(1)
	return false
