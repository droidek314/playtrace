extends GdUnitTestSuite
## Checks the Playtrace autoload script exposes the frozen API from contract 6.1 (T01).


func test_api_matches_contract() -> void:
	var node: Node = auto_free(load("res://addons/playtrace/runtime/playtrace.gd").new())
	var methods: Array[String] = [
		"track", "death", "level", "event", "checkpoint", "complete", "is_recording", "get_detection_report"
	]
	for m: String in methods:
		assert_bool(node.has_method(m)).override_failure_message("missing " + m).is_true()
	for s: String in ["session_started", "session_finished"]:
		assert_bool(node.has_signal(s)).override_failure_message("missing " + s).is_true()
