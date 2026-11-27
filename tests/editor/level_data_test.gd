extends GdUnitTestSuite
## Level filtering: the overlay keeps only what was played in the edited scene (fixtures, M3).

const SANDBOX := "res://demo/sandbox.tscn"
const FIXTURES: Array[String] = ["res://tests/fixtures"]


func test_fixtures_filtered_by_level() -> void:
	var data := PlaytraceLevelData.load_dirs(FIXTURES, SANDBOX)
	# All fixtures but with_feedback.jsonl (level_1) play the sandbox; corrupt lines are skipped.
	assert_int(data.session_count).is_equal(5)
	assert_int(data.deaths.size()).is_equal(10)
	var other := PlaytraceLevelData.load_dirs(FIXTURES, "level_1")
	assert_int(other.session_count).is_equal(1)
	assert_array(Array(other.deaths)).contains_exactly([Vector2(720, 500)])
	assert_int(PlaytraceLevelData.load_dirs(FIXTURES, "res://nope.tscn").session_count).is_equal(0)


func test_only_events_inside_the_level_count() -> void:
	var data := PlaytraceLevelData.new("a")
	var events: Array = [
		{"type": "session_start"},
		{"t": 0, "type": "level_enter", "level": "b"},
		{"t": 1, "type": "pos", "p": [1.0, 1.0, 0]},
		{"t": 2, "type": "level_enter", "level": "a"},
		{"t": 3, "type": "pos", "p": [2.0, 2.0, 0]},
		{"t": 4, "type": "death", "p": [3.0, 3.0, 0]},
		{"t": 5, "type": "pos", "p": "bad"},
		{"t": 6, "type": "level_exit", "level": "a"},
		{"t": 7, "type": "death", "p": [9.0, 9.0, 0]},
	]
	data.add_session(events)
	assert_array(Array(data.paths[0])).contains_exactly([Vector2(2, 2)])
	assert_array(Array(data.deaths)).contains_exactly([Vector2(3, 3)])


func test_death_hotspot_of_fixture_cluster() -> void:
	# Small-scale version of T17 until the generator lands: the 8 spike deaths sit at x 911..918, y 388.
	var data := PlaytraceLevelData.load_dirs(FIXTURES, SANDBOX)
	var sets: Array[PackedVector2Array] = [data.deaths]
	var peak := PlaytraceDensityGrid.build(sets, 16.0).peak_position()
	assert_float(peak.distance_to(Vector2(914.5, 388))).is_less(32.0)


func test_paths_break_at_death_level_change_and_teleport() -> void:
	var data := PlaytraceLevelData.new("a")
	var events: Array = [
		{"t": 0, "type": "level_enter", "level": "a"},
		{"t": 0, "type": "pos", "p": [0.0, 0.0, 0]},
		{"t": 200, "type": "pos", "p": [40.0, 0.0, 0]},
		{"t": 600, "type": "death", "p": [50.0, 0.0, 0]},
		{"t": 1600, "type": "pos", "p": [0.0, 0.0, 0]},
		{"t": 1800, "type": "pos", "p": [900.0, 0.0, 0]},  # 4500 px/s: teleport
		{"t": 2000, "type": "pos", "p": [940.0, 0.0, 0]},
		{"t": 9000, "type": "stuck", "p": [940.0, 0.0, 0]},  # not part of the path, but its time counts
		{"t": 12000, "type": "quit", "p": [940.0, 0.0, 0]},
	]
	data.add_session(events)
	assert_int(data.paths.size()).is_equal(3)
	assert_array(Array(data.paths[0])).contains_exactly([Vector2(0, 0), Vector2(40, 0)])
	assert_array(Array(data.paths[1])).contains_exactly([Vector2(0, 0)])
	assert_array(Array(data.paths[2])).contains_exactly([Vector2(900, 0), Vector2(940, 0)])
	assert_array(_ms(data.path_travel_s)).contains_exactly([200, 0, 200])
	# Stays: until the death, the time before the jump, the hesitation before the quit.
	assert_array(Array(data.stay_points)).contains_exactly([Vector2(40, 0), Vector2(0, 0), Vector2(940, 0)])
	assert_array(_ms(data.stay_seconds)).contains_exactly([400, 200, 10000])
	assert_array(Array(data.deaths)).contains_exactly([Vector2(50, 0)])
	data.add_session([{"t": 0, "type": "level_enter", "level": "a"}, {"t": 0, "type": "level_exit", "level": "a"}])
	assert_int(data.session_count).is_equal(2)


# Seconds to whole milliseconds, so float sums like 0.6 - 0.2 compare exactly.
func _ms(seconds: PackedFloat64Array) -> Array:
	return Array(seconds).map(func(x: float) -> int: return roundi(x * 1000.0))
