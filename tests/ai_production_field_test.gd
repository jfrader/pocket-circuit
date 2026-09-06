extends "res://tests/ai_field_spread_test.gd"


func _run_test() -> void:
	Engine.time_scale = 1.0
	# The general field harness permits a long inspection grace period. These
	# regressions must finish with the real game's eight-second grace instead.
	node_added.connect(func(node: Node) -> void:
		if node is RaceManager:
			(node as RaceManager).finish_grace_seconds = 8.0
	)
	for case: Array in [[&"kitchen", &"classic", 0], [&"workshop", &"wide", 1], [&"office", &"el", 7], [&"kitchen", &"long", 24469], [&"workshop", &"square", 51940], [&"office", &"tall", 42]]:
		if not await _run_theme(case[0], case[1], case[2]):
			return
	print("AI_PRODUCTION_FIELD_TEST PASS six_routes_actual_roster_normal_grace")
	quit(0)
