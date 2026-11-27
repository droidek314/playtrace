extends GdUnitTestSuite
## T21: 1,000 sessions x 10 min of positions computed off the main thread in under 1 s.

const SESSIONS := 1000
const SAMPLES := 3000  # 10 min at one pos every 0.2 s (the worst case: always moving)
const STEP_PX := 44.0  # 220 px/s, the sandbox player's run speed: about 6 deposits per segment at radius 16

var _elapsed_ms := -1
var _thread_id := -1
var _result: Dictionary = {}


func _make_data() -> PlaytraceLevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var data := PlaytraceLevelData.new("res://level.tscn")
	for s in SESSIONS:
		var pts := PackedVector2Array()
		pts.resize(SAMPLES)
		var times := PackedFloat64Array()
		times.resize(SAMPLES + 1)
		var p := Vector2(rng.randf_range(0, 4000), rng.randf_range(0, 2000))
		var heading := rng.randf() * TAU
		for i in SAMPLES:
			heading += rng.randf_range(-0.5, 0.5)
			p = (p + Vector2.from_angle(heading) * STEP_PX).clamp(Vector2.ZERO, Vector2(4000, 2000))
			pts[i] = p
			times[i] = i * 0.2
		times[SAMPLES] = SAMPLES * 0.2
		data.add_path(pts, times)
	return data


func _job(data: PlaytraceLevelData) -> void:
	_thread_id = OS.get_thread_caller_id()
	var t0 := Time.get_ticks_msec()
	_result = PlaytraceHeatmapOverlay.compute(data, 16.0, PlaytraceHeatmapPalette.MAGMA)
	_elapsed_ms = Time.get_ticks_msec() - t0


func test_large_data_computes_off_main_thread_under_1s() -> void:
	var data := _make_data()
	var task := WorkerThreadPool.add_task(_job.bind(data), true, "T21")
	WorkerThreadPool.wait_for_task_completion(task)
	prints("Playtrace: T21 compute of", SESSIONS * SAMPLES, "positions took", _elapsed_ms, "ms")
	assert_int(_thread_id).is_not_equal(OS.get_main_thread_id())
	assert_object(_result["image"]).is_not_null()
	assert_int(_elapsed_ms).is_less(1000)
