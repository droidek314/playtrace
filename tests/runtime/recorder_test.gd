extends GdUnitTestSuite
## Recorder tests T02-T13. Each test drives its own recorder instance with a fake clock and a fake
## "current scene", so no real time passes and the global autoload is not involved.

const SCRIPT := "res://addons/playtrace/runtime/playtrace.gd"
const ROOT_DIR := "user://playtrace_test/recorder"
const LEVEL := "res://test_level.tscn"
const FRAME_MS := 16

var _clock := 0
var _paused := false
var _cur_scene: Node
var _dir := ""


func before_test() -> void:
	_clock = 1000
	_paused = false
	_cur_scene = null
	_dir = ROOT_DIR.path_join(str(Time.get_ticks_usec()))


func after() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT_DIR))


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _make(settings: Dictionary = {}, enabled: bool = true) -> Node:
	var r: Node = auto_free(load(SCRIPT).new())
	add_child(r)
	var hooks := {
		"now": func() -> int: return _clock,
		"scene": func() -> Node: return _cur_scene,
		"paused": func() -> bool: return _paused,
	}
	r._configure(enabled, _dir, hooks, settings)
	return r


## Builds a level scene with one CharacterBody2D called Hero (optionally in group "player").
func _level(path: String = LEVEL, in_group: bool = false) -> CharacterBody2D:
	var root: Node2D = auto_free(Node2D.new())
	root.scene_file_path = path
	var hero := CharacterBody2D.new()
	hero.name = "Hero"
	hero.position = Vector2(100, 200)
	if in_group:
		hero.add_to_group("player")
	root.add_child(hero)
	add_child(root)
	_cur_scene = root
	return hero


## Advances the fake clock by [param ms] in 16 ms frames, moving [param node] at [param velocity] px/s.
func _run(r: Node, ms: int, node: Node2D = null, velocity: Vector2 = Vector2.ZERO) -> void:
	var elapsed := 0
	while elapsed < ms:
		_clock += FRAME_MS
		elapsed += FRAME_MS
		if is_instance_valid(node):
			node.position += velocity * FRAME_MS / 1000.0
		r._step()


func _read(r: Node) -> PlaytraceSession:
	r._writer.flush()
	return PlaytraceSessionReader.read_file(r._writer.path)


func _count(s: PlaytraceSession, type: String) -> int:
	return s.events_of_type(type).size()


func _at(e: Dictionary) -> Vector2:
	return Vector2(e["p"][0], e["p"][1])


## Converts every number to float so written and read-back values compare equal.
func _norm(v: Variant) -> Variant:
	if v is int:
		return float(v)
	if v is Array:
		return (v as Array).map(_norm)
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _norm(v[k])
		return d
	return v


# --- T02 -------------------------------------------------------------------------------------


func test_t02_every_event_type_round_trips() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 100)
	r.checkpoint("mid")
	r.event(&"opened_door", {"door": "red", "n": 2})
	_run(r, 300, hero, Vector2(100, 0))
	r.complete()
	r.level("bonus")
	_run(r, 9000)
	hero.position += Vector2(200, 0)
	_run(r, 32)
	r.death("spikes")
	r._writer.write({"t": 9999, "type": "feedback", "p": [1.0, 2.0, 0], "data": {"text": "hi", "screenshot": "1.jpg"}})
	r._finish_session()
	var lines := FileAccess.get_file_as_string(r._writer.path).split("\n", false)
	var s := PlaytraceSessionReader.read_file(r._writer.path)
	assert_array(s.warnings).is_empty()
	assert_int(s.events.size()).is_equal(lines.size() - 1)
	var types := {}
	for i in s.events.size():
		var written: Variant = JSON.parse_string(lines[i + 1])
		assert_that(_norm(s.events[i])).is_equal(_norm(written))
		types[s.events[i]["type"]] = true
	for t: String in PlaytraceSessionReader.KNOWN_TYPES:
		assert_bool(types.has(t)).override_failure_message("missing type " + t).is_true()


# --- T03 -------------------------------------------------------------------------------------


func test_t03_position_sampling_rate() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 10000, hero, Vector2(100, 0))
	assert_int(_count(_read(r), "pos")).is_between(49, 52)


func test_t03_no_samples_when_moving_less_than_2px() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 10000, hero, Vector2(0.1, 0))
	assert_int(_count(_read(r), "pos")).is_equal(1)  # only the first sample on level enter


# --- T04 -------------------------------------------------------------------------------------


func test_t04_standing_still_8s_gives_one_stuck() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 8200, hero)
	hero.position += Vector2(100, 0)
	_run(r, 500, hero)
	var stuck := _read(r).events_of_type("stuck")
	assert_int(stuck.size()).is_equal(1)
	assert_float(stuck[0]["data"]["seconds"]).is_equal_approx(8.2, 0.1)
	assert_float(_at(stuck[0]).distance_to(Vector2(100, 200))).is_less(1.0)


func test_t04_jitter_under_16px_still_counts() -> void:
	var r := _make()
	var hero := _level()
	for i in 90:
		hero.position = Vector2(100 + (7 if i % 2 == 0 else -7), 200)
		_run(r, 100)
	hero.position = Vector2(400, 200)
	_run(r, 100)
	assert_int(_count(_read(r), "stuck")).is_equal(1)


func test_t04_paused_time_does_not_count() -> void:
	var r := _make()
	var hero := _level()
	_paused = true
	_run(r, 9000, hero)
	_paused = false
	_run(r, 2000, hero)
	hero.position += Vector2(100, 0)
	_run(r, 100, hero)
	assert_int(_count(_read(r), "stuck")).is_equal(0)


func test_t04_short_stop_is_not_stuck() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 5000, hero)
	hero.position += Vector2(100, 0)
	_run(r, 100, hero)
	assert_int(_count(_read(r), "stuck")).is_equal(0)


# --- T05 -------------------------------------------------------------------------------------


func test_t05_close_request_writes_quit_last() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 1000, hero, Vector2(50, 0))
	r._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var s := PlaytraceSessionReader.read_file(r._writer.path)
	assert_str(s.events[-1]["type"]).is_equal("quit")
	assert_str(s.outcome()).is_equal("quit")
	assert_bool(r.is_recording()).is_false()


func test_t05_killed_writer_loses_at_most_5s() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 23000, hero, Vector2(50, 0))
	var last_t: int = _clock - r._start_ms
	# Read the file as it is on disk without flushing or closing: as if the game crashed now.
	var s := PlaytraceSessionReader.read_file(r._writer.path)
	assert_array(s.warnings).is_empty()
	assert_int(last_t - s.duration_ms()).is_less_equal(5000)
	assert_int(_count(s, "pos")).is_greater(50)


# --- T06 -------------------------------------------------------------------------------------


func test_t06_overhead_under_0_1_ms_per_frame() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 100)
	var start := Time.get_ticks_usec()
	for i in 10000:
		_clock += FRAME_MS
		hero.position.x += 1.5
		r._step()
	var avg_ms := (Time.get_ticks_usec() - start) / 10000.0 / 1000.0
	prints("Playtrace: recorder overhead %.4f ms/frame" % avg_ms)
	assert_float(avg_ms).is_less(0.1)


# --- T07 -------------------------------------------------------------------------------------


func test_t07_disabled_records_nothing() -> void:
	var r := _make({}, false)
	var hero := _level()
	_run(r, 1000, hero, Vector2(100, 0))
	r.track(hero)
	r.death()
	r.level("x")
	r.event(&"e")
	r.checkpoint("c")
	r.complete()
	r._finish_session()
	assert_bool(r.is_recording()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(_dir)).is_false()


# --- T08 -------------------------------------------------------------------------------------


func test_t08_zero_code_player_removal_is_a_death() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 500, hero, Vector2(100, 0))
	var at := hero.global_position
	hero.free()
	_run(r, 100)
	var s := _read(r)
	var deaths := s.events_of_type("death")
	assert_int(deaths.size()).is_equal(1)
	assert_str(deaths[0]["data"]["cause"]).is_equal("auto")
	assert_float(_at(deaths[0]).distance_to(at)).is_less(1.0)
	assert_str(s.header["detection"]["deaths"]).is_equal("node_removal")
	assert_str(s.header["detection"]["player"]).is_equal("Hero (CharacterBody2D)")


# --- T09 -------------------------------------------------------------------------------------


func test_t09_group_player_wins_over_first_body() -> void:
	_level()
	var grouped := Node2D.new()
	grouped.name = "Chosen"
	grouped.add_to_group("player")
	_cur_scene.add_child(grouped)
	var r := _make()
	_run(r, 50)
	assert_str(r.get_detection_report()["player"]).is_equal("Chosen (Node2D)")


func test_t09_no_player_warns_and_keeps_running() -> void:
	var root: Node2D = auto_free(Node2D.new())
	root.scene_file_path = LEVEL
	add_child(root)
	_cur_scene = root
	var r := _make()
	_run(r, 2000)
	r.checkpoint("still fine")
	var s := _read(r)
	assert_str(s.header["detection"]["player"]).is_equal("")
	assert_array(s.header["detection"]["warnings"]).contains(["player_not_found"])
	assert_array(r.get_detection_report()["warnings"]).contains(["player_not_found"])
	assert_int(_count(s, "checkpoint")).is_equal(1)


func test_t09_player_found_later_after_scene_change() -> void:
	var root: Node2D = auto_free(Node2D.new())
	root.scene_file_path = "res://menu.tscn"
	add_child(root)
	_cur_scene = root
	var r := _make()
	_run(r, 200)
	_level()
	_run(r, 200)
	assert_str(r.get_detection_report()["player"]).is_equal("Hero (CharacterBody2D)")
	assert_array(_read(r).levels()).is_equal(["res://menu.tscn", LEVEL])


# --- T10 -------------------------------------------------------------------------------------


func _reload(same_path: bool = true) -> CharacterBody2D:
	var old := _cur_scene
	old.free()
	return _level(LEVEL if same_path else "res://other.tscn")


func test_t10_scene_reload_within_1s_is_one_death() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 500, hero, Vector2(100, 0))
	hero = _reload()
	_run(r, 200, hero)
	var s := _read(r)
	assert_int(_count(s, "death")).is_equal(1)
	assert_int(_count(s, "level_enter")).is_equal(2)


func test_t10_switching_to_another_level_is_not_a_death() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 500, hero)
	hero = _reload(false)
	_run(r, 200, hero)
	assert_int(_count(_read(r), "death")).is_equal(0)


func test_t10_reload_later_than_1s_is_not_a_death() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 500, hero)
	var old := _cur_scene
	old.free()
	_cur_scene = null
	_run(r, 1500)
	hero = _level()
	_run(r, 200, hero)
	assert_int(_count(_read(r), "death")).is_equal(0)


# --- T11 -------------------------------------------------------------------------------------


func test_t11_manual_mode_records_only_explicit_calls() -> void:
	var r := _make({PlaytraceSettings.SETUP_MODE: "manual"})
	var hero := _level()
	_run(r, 1000, hero, Vector2(100, 0))
	var s := _read(r)
	assert_int(s.events.size()).is_equal(0)
	assert_str(s.header["detection"]["mode"]).is_equal("manual")
	r.level("level_1")
	r.track(hero)
	_run(r, 1000, hero, Vector2(100, 0))
	r.death()
	hero.free()
	_run(r, 200)
	s = _read(r)
	assert_array(s.levels()).is_equal(["level_1"])
	assert_int(_count(s, "pos")).is_greater(3)
	assert_int(_count(s, "death")).is_equal(1)
	assert_str(s.events_of_type("death")[0]["data"]["cause"]).is_equal("manual")


# --- T12 -------------------------------------------------------------------------------------


func test_t12_explicit_death_takes_over_from_auto() -> void:
	var r := _make()
	var hero := _level()
	_run(r, 300, hero, Vector2(100, 0))
	hero.free()  # auto death 1
	_run(r, 100)
	hero = CharacterBody2D.new()
	_cur_scene.add_child(hero)
	_run(r, 600, hero, Vector2(100, 0))
	r.death("lava")  # manual death 2; auto deaths are now off
	hero.free()  # same death, must not count again
	_run(r, 100)
	var old := _cur_scene
	old.free()
	_level()
	_run(r, 200)  # reload after the manual death: not counted either
	var causes: Array = _read(r).events_of_type("death").map(func(e: Dictionary) -> String: return e["data"]["cause"])
	assert_array(causes).is_equal(["auto", "lava"])
	assert_str(r.get_detection_report()["deaths"]).is_equal("manual")


# --- T13 -------------------------------------------------------------------------------------


## Scripted run: walk right, stand still 9 s, walk on, die, then quit.
func _scripted_run(manual: bool) -> PlaytraceSession:
	_clock = 1000
	_dir = ROOT_DIR.path_join("t13_%s" % manual)
	var r := _make({PlaytraceSettings.SETUP_MODE: "manual" if manual else "auto"})
	var hero := _level()
	if manual:
		r.level(LEVEL)
		r.track(hero)
	_run(r, 2000, hero, Vector2(150, 0))
	_run(r, 9000, hero)
	_run(r, 1000, hero, Vector2(150, -20))
	if manual:
		r.death("auto")
	hero.free()
	_run(r, 100)
	r._finish_session()
	_cur_scene.free()
	return PlaytraceSessionReader.read_file(r._writer.path)


func test_t13_manual_and_auto_agree() -> void:
	var auto := _scripted_run(false)
	var manual := _scripted_run(true)
	for type: String in ["death", "stuck", "quit"]:
		var a := auto.events_of_type(type)
		var m := manual.events_of_type(type)
		assert_int(a.size()).override_failure_message(type).is_equal(1)
		assert_int(m.size()).override_failure_message(type).is_equal(a.size())
		assert_float(_at(a[0]).distance_to(_at(m[0]))).override_failure_message(type).is_less_equal(4.0)


# --- header and signals ----------------------------------------------------------------------


func test_header_and_signals() -> void:
	var r := _make()
	var started: Array[String] = []
	var finished: Array[String] = []
	r.session_started.connect(func(id: String) -> void: started.append(id))
	r.session_finished.connect(func(id: String, path: String) -> void: finished.append(path))
	var hero := _level()
	_run(r, 100, hero)
	r._finish_session()
	var s := PlaytraceSessionReader.read_file(r._writer.path)
	assert_int(int(s.header["schema"])).is_equal(1)
	assert_str(s.header["session"]).has_length(36)
	assert_str(s.header["started_utc"]).ends_with("Z")
	assert_array(started).is_equal([s.header["session"]])
	assert_array(finished).is_equal([r._writer.path])
