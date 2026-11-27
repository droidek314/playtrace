extends GdUnitTestSuite
## T21: 1,000 sessions x 10 min of positions computed off the main thread in under 1 s.

const SESSIONS := 1000
const SAMPLES := 3000  # 10 min at one pos every 0.2 s (the worst case: always moving)

var _elapsed_ms := -1
var _thread_id := -1
var _result: Dictionary = {}


func _make_data() -> PlaytraceLevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var data := PlaytraceLevelData.new("res://level.tscn")
	data.bounds = Rect2(0, 0, 4000, 2000)  # PlaytraceLevelData.add_session tracks this while loading
	for s in SESSIONS:
		var pts := PackedVector2Array()
		pts.resize(SAMPLES)
		var p := Vector2(rng.randf_range(0, 4000), rng.randf_range(0, 2000))
		for i in SAMPLES:
			p = (p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))).clamp(Vector2.ZERO, Vector2(4000, 2000))
			pts[i] = p
		data.paths.append(pts)
	return data


func _job(data: PlaytraceLevelData) -> void:
	_thread_id = OS.get_thread_caller_id()
	var t0 := Time.get_ticks_msec()
	_result = PlaytraceHeatmapOverlay.compute(data, 24.0, PlaytraceHeatmapPalette.MAGMA)
	_elapsed_ms = Time.get_ticks_msec() - t0


func test_large_data_computes_off_main_thread_under_1s() -> void:
	var data := _make_data()
	var task := WorkerThreadPool.add_task(_job.bind(data), true, "T21")
	WorkerThreadPool.wait_for_task_completion(task)
	prints("Playtrace: T21 compute of", SESSIONS * SAMPLES, "positions took", _elapsed_ms, "ms")
	assert_int(_thread_id).is_not_equal(OS.get_main_thread_id())
	assert_object(_result["image"]).is_not_null()
	assert_int(_elapsed_ms).is_less(1000)
