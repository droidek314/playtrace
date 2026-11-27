extends GdUnitTestSuite
## T26: each setup_health fixture triggers its warning exactly once; the main fixtures trigger none.

const LEVEL := "res://demo/sandbox.tscn"
const HEALTH_DIR := "res://tests/fixtures/setup_health/"


func _records(paths: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: String in paths:
		out.append(PlaytraceSessionLibrary.make_record(PlaytraceSessionReader.read_file(p), p, LEVEL))
	return out


func test_each_fixture_triggers_its_warning_once() -> void:
	var cases := {
		"no_player.jsonl": PlaytraceSchema.WARN_PLAYER_NOT_FOUND,
		"never_moved.jsonl": PlaytraceSchema.WARN_PLAYER_NEVER_MOVED,
		"reloads_without_deaths.jsonl": PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS,
	}
	for f: String in cases:
		var w := PlaytraceSetupHealth.warnings(_records([HEALTH_DIR + f]))
		assert_array(w).override_failure_message(f).contains_exactly([cases[f]])


func test_all_three_together_each_once() -> void:
	var w := PlaytraceSetupHealth.warnings(_records(PlaytraceSessionReader.list_sessions(HEALTH_DIR.trim_suffix("/"))))
	(
		assert_array(w)
		. contains_exactly_in_any_order(
			[
				PlaytraceSchema.WARN_PLAYER_NOT_FOUND,
				PlaytraceSchema.WARN_PLAYER_NEVER_MOVED,
				PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS,
			]
		)
	)


func test_main_fixtures_trigger_none() -> void:
	var records := _records(PlaytraceSessionReader.list_sessions("res://tests/fixtures"))
	assert_int(records.size()).is_equal(6)
	assert_array(PlaytraceSetupHealth.warnings(records)).is_empty()


func test_card_lines_and_checklist_ticks() -> void:
	var good := _records(PlaytraceSessionReader.list_sessions("res://tests/fixtures"))
	for line: Dictionary in PlaytraceSetupHealth.card(good):
		assert_bool(line.ok).override_failure_message(line.label).is_true()
	var bad := _records([HEALTH_DIR + "no_player.jsonl"])
	var player: Dictionary = PlaytraceSetupHealth.card(bad)[1]
	assert_bool(player.ok).is_false()
	assert_str(player.warning).is_equal(PlaytraceSchema.WARN_PLAYER_NOT_FOUND)
	var seen := PlaytraceSetupHealth.seen_types(good)
	assert_bool(seen.has(PlaytraceSchema.CHECKPOINT)).is_true()
	assert_bool(seen.has(PlaytraceSchema.FEEDBACK)).is_true()
