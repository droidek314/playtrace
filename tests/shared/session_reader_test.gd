extends GdUnitTestSuite
## T15 reader robustness plus the PlaytraceSession helpers, checked against tests/fixtures/README.md.

const FIXTURES := "res://tests/fixtures/"


func _read(file_name: String) -> PlaytraceSession:
	return PlaytraceSessionReader.read_file(FIXTURES + file_name)


func test_valid_fixtures_read_without_warnings() -> void:
	for f: String in ["completed.jsonl", "quit.jsonl", "many_deaths.jsonl", "stuck.jsonl", "with_feedback.jsonl"]:
		var s := _read(f)
		assert_array(s.warnings).override_failure_message(f + ": " + str(s.warnings)).is_empty()
		assert_str(s.header.get("type")).is_equal("session_start")
		assert_int(int(s.header.get("schema"))).is_equal(1)


func test_outcomes_and_deaths_match_fixture_table() -> void:
	var expected := {
		"completed.jsonl": ["completed", 0],
		"quit.jsonl": ["quit", 0],
		"many_deaths.jsonl": ["quit", 9],
		"stuck.jsonl": ["completed", 0],
		"with_feedback.jsonl": ["quit", 1],
		"corrupt.jsonl": ["unknown", 1],
	}
	for f: String in expected:
		var s := _read(f)
		assert_str(s.outcome()).override_failure_message(f).is_equal(expected[f][0])
		assert_int(s.events_of_type("death").size()).override_failure_message(f).is_equal(expected[f][1])


func test_corrupt_file_keeps_valid_events_and_warns_once() -> void:
	var s := _read("corrupt.jsonl")
	var types: Array[String] = []
	for e: Dictionary in s.events:
		types.append(e["type"])
	assert_array(types).is_equal(["level_enter", "pos", "pos", "death"])
	assert_int(s.warnings.size()).is_equal(1)
	assert_str(s.warnings[0]).contains("4 corrupt")


func test_unknown_fields_are_kept_but_harmless() -> void:
	var pos := _read("corrupt.jsonl").events_of_type("pos")
	assert_int(pos[1]["t"]).is_equal(1000)
	assert_array(pos[1]["p"]).is_equal([128.0, 400.0, 0.0])


func test_helpers() -> void:
	var s := _read("completed.jsonl")
	assert_array(s.levels()).is_equal(["res://demo/sandbox.tscn"])
	assert_int(s.duration_ms()).is_equal(12400)
	assert_str(_read("with_feedback.jsonl").events_of_type("feedback")[0]["data"]["text"]).is_equal(
		"Is this ledge reachable?"
	)


func test_missing_file_returns_empty_session_with_warning() -> void:
	var s := PlaytraceSessionReader.read_file("res://does/not/exist.jsonl")
	assert_array(s.events).is_empty()
	assert_int(s.warnings.size()).is_equal(1)


func test_list_sessions_finds_only_jsonl_sorted() -> void:
	var files := PlaytraceSessionReader.list_sessions("res://tests/fixtures")
	assert_int(files.size()).is_equal(6)
	assert_str(files[0]).is_equal("res://tests/fixtures/completed.jsonl")
	assert_array(PlaytraceSessionReader.list_sessions("res://no_such_dir")).is_empty()
