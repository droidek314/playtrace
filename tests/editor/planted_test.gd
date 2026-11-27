extends GdUnitTestSuite
## T17-T19: the heatmap finds what the seeded generator planted (tools/planted.json is ground truth).
## Sessions go through the real path: generator -> .jsonl files -> PlaytraceSessionReader -> level data.

const GOLDEN := "res://tests/golden/heatmap_seed1_magma.png"
## Max share of differing pixels for T19, and the per-channel difference (of 255) that counts as differing.
const GOLDEN_MAX_DIFF := 0.01
const GOLDEN_CHANNEL_TOLERANCE := 3

var _gen := PlaytraceSessionGenerator.new()
var _level: String = _gen.planted()["level"]


func _load(seed_value: int, count: int) -> PlaytraceLevelData:
	var dir := "user://playtrace_tests/editor_seed_%d" % seed_value
	for f: String in PlaytraceSessionReader.list_sessions(dir):
		DirAccess.remove_absolute(f)
	_gen.write(seed_value, count, _level, dir)
	var data := PlaytraceLevelData.load_dirs([dir] as Array[String], _level)
	for f: String in PlaytraceSessionReader.list_sessions(dir):
		DirAccess.remove_absolute(f)
	return data


func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func test_t17_top_death_hotspot_on_planted_cluster() -> void:
	var center := _v(_gen.planted()["death_cluster"]["center"])
	for seed_value in range(1, 21):
		var data := _load(seed_value, 40)
		var sets: Array[PackedVector2Array] = [data.deaths]
		var peak := PlaytraceDensityGrid.build(sets, 16.0).peak_position()
		(
			assert_float(peak.distance_to(center))
			. override_failure_message("seed %d: hotspot at %s" % [seed_value, peak])
			. is_less(32.0)
		)


func test_t18_unvisited_area_stays_cold() -> void:
	var data := _load(1, 200)
	var grid := PlaytraceDensityGrid.build(data.paths, 24.0, data.bounds)
	var r: Array = _gen.planted()["unvisited_area"]["rect"]
	var rect := Rect2(r[0], r[1], r[2], r[3])
	var hottest := 0.0
	for y in grid.height:
		for x in grid.width:
			if rect.has_point(grid.origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * grid.cell_size):
				hottest = maxf(hottest, grid.values[y * grid.width + x])
	assert_float(hottest).is_less(grid.max_value * 0.01)


func test_t19_golden_heatmap_image() -> void:
	var result := PlaytraceHeatmapOverlay.compute(_load(1, 200), 24.0, PlaytraceHeatmapPalette.MAGMA)
	var image: Image = result["image"]
	# To regenerate after an intended visual change: PLAYTRACE_UPDATE_GOLDEN=1, run this suite, commit the PNG.
	if OS.get_environment("PLAYTRACE_UPDATE_GOLDEN") == "1":
		image.save_png(ProjectSettings.globalize_path(GOLDEN))
		prints("Playtrace: wrote golden image", GOLDEN)
	assert_bool(FileAccess.file_exists(GOLDEN)).override_failure_message("missing " + GOLDEN).is_true()
	var golden := Image.load_from_file(ProjectSettings.globalize_path(GOLDEN))
	golden.convert(Image.FORMAT_RGBA8)
	assert_vector(Vector2(golden.get_size())).is_equal(Vector2(image.get_size()))
	var a := image.get_data()
	var b := golden.get_data()
	var differing := 0
	for i in range(0, a.size(), 4):
		for c in 4:
			if absi(a[i + c] - b[i + c]) > GOLDEN_CHANNEL_TOLERANCE:
				differing += 1
				break
	assert_float(float(differing) / (a.size() / 4)).is_less(GOLDEN_MAX_DIFF)
