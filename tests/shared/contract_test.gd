extends GdUnitTestSuite
## Checks the shared types from contracts 6.2 and 6.3 load and keep their shape (T01).


func test_reader_returns_session() -> void:
	var session := PlaytraceSessionReader.read_file("res://tests/fixtures/completed.jsonl")
	assert_object(session).is_not_null()
	assert_array(PlaytraceSessionReader.list_sessions()).is_not_null()


func test_settings_defaults_cover_all_keys() -> void:
	var d := PlaytraceSettings.defaults()
	assert_int(d.size()).is_equal(14)
	assert_str(d[PlaytraceSettings.SETUP_MODE]).is_equal("auto")
	assert_float(d[PlaytraceSettings.STUCK_SECONDS]).is_equal(8.0)
	assert_str(d[PlaytraceSettings.FEEDBACK_KEY]).is_equal("F8")
