extends GdUnitTestSuite
## T22: each Sessions filter returns exactly the expected fixture sessions.

const SANDBOX := "res://demo/sandbox.tscn"
const DIRS: Array[String] = ["res://tests/fixtures", "res://tests/fixtures/setup_health"]

var _records: Array[Dictionary] = []


func before() -> void:
	_records = PlaytraceSessionLibrary.load_dirs(DIRS, SANDBOX)


func _names(f: Dictionary) -> Array:
	var by := PlaytraceSessionLibrary.NO_FILTER.duplicate()
	by.merge(f, true)
	var out: Array = []
	for r: Dictionary in PlaytraceSessionLibrary.filter(_records, by):
		out.append(str(r.summary.path).get_file().get_basename())
	out.sort()
	return out


func test_no_filter_returns_all_nine() -> void:
	assert_int(_names({}).size()).is_equal(9)


func test_level_filter() -> void:
	assert_array(_names({"level": "level_1"})).contains_exactly(["with_feedback"])
	assert_int(_names({"level": SANDBOX}).size()).is_equal(8)


func test_outcome_filter() -> void:
	assert_array(_names({"outcome": "completed"})).contains_exactly(["completed", "stuck"])
	assert_array(_names({"outcome": "unknown"})).contains_exactly(["corrupt"])
	var quits := ["many_deaths", "never_moved", "no_player", "quit", "reloads_without_deaths", "with_feedback"]
	assert_array(_names({"outcome": "quit"})).contains_exactly(quits)


func test_build_filter() -> void:
	assert_int(_names({"build": "0.1.0"}).size()).is_equal(9)
	assert_array(_names({"build": "9.9.9"})).is_empty()


func test_date_range_filter_is_inclusive() -> void:
	assert_array(_names({"date_from": "2026-11-21"})).contains_exactly(
		["never_moved", "no_player", "reloads_without_deaths"]
	)
	assert_int(_names({"date_to": "2026-11-20"}).size()).is_equal(6)
	assert_int(_names({"date_from": "2026-11-20", "date_to": "2026-11-20"}).size()).is_equal(6)
	assert_array(_names({"date_from": "2026-11-22"})).is_empty()


func test_combined_filters_and_summary() -> void:
	assert_array(_names({"level": SANDBOX, "outcome": "completed", "date_to": "2026-11-20"})).contains_exactly(
		["completed", "stuck"]
	)
	var many: Dictionary = (
		PlaytraceSessionLibrary.filter(_records, {"outcome": "quit", "date_to": "2026-11-20"})[0].summary
	)
	assert_str(many.build).is_equal("0.1.0")


func test_combine_merges_level_parts_with_session_indices() -> void:
	var sandbox := PlaytraceSessionLibrary.filter(_records, {"level": SANDBOX, "date_to": "2026-11-20"})
	var data := PlaytraceSessionLibrary.combine(sandbox, SANDBOX)
	assert_int(data.session_count).is_equal(5)
	assert_int(data.deaths.size()).is_equal(10)
	assert_int(data.death_session.size()).is_equal(10)
	assert_int(data.stuck_points.size()).is_equal(1)
	assert_float(data.stuck_seconds[0]).is_equal_approx(12.4, 0.001)
	assert_int(data.quit_points.size()).is_equal(2)  # quit.jsonl and many_deaths.jsonl; corrupt's quit is cut
