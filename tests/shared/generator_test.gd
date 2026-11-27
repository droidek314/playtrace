extends GdUnitTestSuite
## T14 generator determinism, plus checks that every planted feature is really in the data.

const LEVEL := "res://demo/sandbox.tscn"
const OUT_A := "user://playtrace_test/gen_a"
const OUT_B := "user://playtrace_test/gen_b"

var _gen: PlaytraceSessionGenerator
var _planted: Dictionary
var _sessions: Array[PlaytraceSession] = []


func before() -> void:
	_gen = PlaytraceSessionGenerator.new()
	_planted = _gen.planted()
	var dir := "user://playtrace_test/truth"
	_gen.write(1, 200, LEVEL, dir)
	for path: String in PlaytraceSessionReader.list_sessions(dir):
		_sessions.append(PlaytraceSessionReader.read_file(path))


func after() -> void:
	for d: String in [OUT_A, OUT_B, "user://playtrace_test/truth"]:
		var abs_dir := ProjectSettings.globalize_path(d)
		for f: String in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))


func _center(feature: String) -> Vector2:
	var c: Array = _planted[feature]["center"]
	return Vector2(c[0], c[1])


func _at(e: Dictionary) -> Vector2:
	return Vector2(e["p"][0], e["p"][1])


func test_same_seed_gives_byte_identical_files() -> void:
	_gen.write(7, 30, LEVEL, OUT_A)
	_gen.write(7, 30, LEVEL, OUT_B)
	var a := PlaytraceSessionReader.list_sessions(OUT_A)
	var b := PlaytraceSessionReader.list_sessions(OUT_B)
	assert_int(a.size()).is_equal(30)
	for i in a.size():
		assert_str(a[i].get_file()).is_equal(b[i].get_file())
		assert_bool(FileAccess.get_file_as_bytes(a[i]) == FileAccess.get_file_as_bytes(b[i])).is_true()


func test_different_seed_gives_different_sessions() -> void:
	assert_array(_gen.generate(1, 5, LEVEL).keys()).is_not_equal(_gen.generate(2, 5, LEVEL).keys())


func test_generated_files_are_clean_schema_v1() -> void:
	for s: PlaytraceSession in _sessions:
		assert_array(s.warnings).is_empty()
		assert_int(int(s.header["schema"])).is_equal(1)
		assert_array(s.levels()).is_equal([LEVEL])
		assert_str(s.outcome()).is_not_equal("unknown")


func test_deaths_are_in_planted_cluster() -> void:
	var count := 0
	for s: PlaytraceSession in _sessions:
		for e: Dictionary in s.events_of_type("death"):
			count += 1
			assert_float(_at(e).distance_to(_center("death_cluster"))).is_less(32.0)
	assert_int(count).is_greater(100)


func test_stuck_events_are_in_planted_zone() -> void:
	var count := 0
	for s: PlaytraceSession in _sessions:
		for e: Dictionary in s.events_of_type("stuck"):
			count += 1
			assert_float(_at(e).distance_to(_center("stuck_zone"))).is_less(_planted["stuck_zone"]["radius"])
			assert_float(e["data"]["seconds"]).is_greater_equal(8.0)
	assert_int(count).is_greater(10)


func test_quits_are_at_planted_quit_point() -> void:
	var count := 0
	for s: PlaytraceSession in _sessions:
		for e: Dictionary in s.events_of_type("quit"):
			count += 1
			assert_float(_at(e).distance_to(_center("quit_point"))).is_less(_planted["quit_point"]["radius"])
	assert_int(count).is_greater(20)


func test_nobody_enters_unvisited_area() -> void:
	var r: Array = _planted["unvisited_area"]["rect"]
	var rect := Rect2(r[0], r[1], r[2], r[3])
	for s: PlaytraceSession in _sessions:
		for e: Dictionary in s.events:
			if e.has("p"):
				assert_bool(rect.has_point(_at(e))).is_false()


func test_backtrack_loop_reaches_dead_end_and_returns() -> void:
	var to: Array = _planted["backtrack_loop"]["to"]
	var loops := 0
	for s: PlaytraceSession in _sessions:
		var reached := false
		for e: Dictionary in s.events_of_type("pos"):
			if _at(e).distance_to(Vector2(to[0], to[1])) < 8.0:
				reached = true
			elif reached and e["p"][0] < 1300.0:
				loops += 1
				break
	assert_int(loops).is_greater(50)
