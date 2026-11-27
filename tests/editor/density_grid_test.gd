extends GdUnitTestSuite
## T16: density grid correctness, plus the colour step that turns it into an image.


func _sets(points: Array) -> Array[PackedVector2Array]:
	var sets: Array[PackedVector2Array] = [PackedVector2Array(points)]
	return sets


func test_single_point_peaks_in_its_cell() -> void:
	var p := Vector2(137.3, -42.8)
	var grid := PlaytraceDensityGrid.build(_sets([p]), 8.0)
	assert_object(grid.cell_of(grid.peak_position())).is_equal(grid.cell_of(p))
	assert_float(grid.total()).is_equal_approx(1.0, 0.001)


func test_total_mass_equals_event_count() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sets: Array[PackedVector2Array] = []
	var n := 0
	for s in 12:  # several sessions, so the parallel binning path is used
		var pts := PackedVector2Array()
		for i in 500:
			pts.append(Vector2(rng.randf_range(-300, 900), rng.randf_range(0, 400)))
		n += pts.size()
		sets.append(pts)
	var grid := PlaytraceDensityGrid.build(sets, 16.0)
	assert_float(grid.total()).is_equal_approx(float(n), n * 0.001)


func test_gaussian_shape_is_symmetric_and_falls_off() -> void:
	var grid := PlaytraceDensityGrid.build(_sets([Vector2(500, 500)]), 20.0)
	var c := grid.value_at(Vector2(500, 500))
	var at_sigma := grid.value_at(Vector2(520, 500))
	assert_float(grid.value_at(Vector2(480, 500))).is_equal_approx(at_sigma, at_sigma * 0.05)
	assert_float(grid.value_at(Vector2(500, 520))).is_equal_approx(at_sigma, at_sigma * 0.05)
	# exp(-1/2) = 0.607 at one sigma; loose because of cell sampling.
	assert_float(at_sigma / c).is_between(0.45, 0.75)
	assert_float(grid.value_at(Vector2(600, 500))).is_less(c * 0.001)


func test_empty_input_gives_empty_grid() -> void:
	var grid := PlaytraceDensityGrid.build([] as Array[PackedVector2Array], 16.0)
	assert_int(grid.values.size()).is_equal(0)
	assert_object(PlaytraceHeatmapPalette.colorize(grid, PlaytraceHeatmapPalette.MAGMA)).is_null()


func test_explicit_bounds_and_huge_levels_stay_capped() -> void:
	var grid := PlaytraceDensityGrid.build(_sets([Vector2(10, 10)]), 2.0, Rect2(0, 0, 100000, 100000))
	assert_int(grid.width * grid.height).is_less_equal(PlaytraceDensityGrid.MAX_CELLS + grid.width + grid.height + 1)


func test_colorize_is_transparent_where_empty_and_never_opaque() -> void:
	var grid := PlaytraceDensityGrid.build(_sets([Vector2(0, 0)]), 8.0)
	for id: int in [PlaytraceHeatmapPalette.MAGMA, PlaytraceHeatmapPalette.VIRIDIS]:
		var img := PlaytraceHeatmapPalette.colorize(grid, id)
		assert_int(img.get_width()).is_equal(grid.width)
		assert_float(img.get_pixel(0, 0).a).is_equal(0.0)
		var peak := grid.cell_of(grid.peak_position())
		assert_float(img.get_pixel(peak.x, peak.y).a).is_between(0.9, 0.96)


# T16 for movement. The exact rule (PlaytraceLevelData): for samples a -> b with dt seconds,
# min(dt, 0.2 s) is travel spread along a -> b and the rest is a stay at a; the last sample stays until
# the path ended. So a path adds exactly its duration, times[-1] - times[0], and the grid total is the
# total recorded time in seconds.
func test_path_mass_equals_recorded_time() -> void:
	var data := PlaytraceLevelData.new("l")
	# 5 s standing at (40, 0), 3.4 s before the path ended: duration 9 s.
	data.add_path(
		PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(80, 10), Vector2(80, 10)]),
		PackedFloat64Array([0.0, 0.2, 5.4, 5.6, 9.0])
	)
	data.add_path(PackedVector2Array([Vector2(300, 300), Vector2(330, 260)]), PackedFloat64Array([12.0, 12.2, 12.2]))
	var grid := PlaytraceDensityGrid.build_level(data, 8.0)
	assert_float(grid.total()).is_equal_approx(9.2, 9.2 * 0.001)


func test_standing_still_counts_at_the_earlier_sample() -> void:
	var data := PlaytraceLevelData.new("l")
	data.add_path(PackedVector2Array([Vector2(0, 0), Vector2(200, 0)]), PackedFloat64Array([0.0, 6.0, 6.0]))
	var grid := PlaytraceDensityGrid.build_level(data, 8.0)
	assert_object(grid.cell_of(grid.peak_position())).is_equal(grid.cell_of(Vector2(0, 0)))
	# The 0.2 s of travel is spread evenly: the middle of the segment is warm but far below the stop.
	var mid := grid.value_at(Vector2(100, 0))
	assert_float(mid).is_greater(0.0)
	assert_float(mid).is_less(grid.value_at(Vector2(0, 0)) * 0.05)
	assert_float(grid.value_at(Vector2(60, 0))).is_equal_approx(mid, mid * 0.05)  # no beads along the path
	assert_float(grid.value_at(Vector2(70, 0))).is_equal_approx(mid, mid * 0.05)


# The fast splat (used for large data) must keep the mass and match the exact splat closely
# once many paths overlap: 100 runs along the same route at 220 px/s, sampled at the same spots.
func test_fast_splat_matches_exact_on_many_paths() -> void:
	var data := PlaytraceLevelData.new("l")
	for s in 100:
		var pts := PackedVector2Array()
		var times := PackedFloat64Array()
		for i in 40:
			pts.append(Vector2(64 + i * 44, 432 - i * 3))
			times.append(i * 0.2)
		times.append(40 * 0.2)
		data.add_path(pts, times)
	var exact := PlaytraceDensityGrid.build_level(data, 16.0, PlaytraceDensityGrid.SPLAT_EXACT)
	var fast := PlaytraceDensityGrid.build_level(data, 16.0, PlaytraceDensityGrid.SPLAT_FAST)
	assert_float(fast.total()).is_equal_approx(exact.total(), exact.total() * 0.001)
	var worst := 0.0
	for x in range(200, 1600, 4):
		var p := Vector2(x, 432 - (x - 64) * 3.0 / 44.0)
		worst = maxf(worst, absf(fast.value_at(p) - exact.value_at(p)) / exact.value_at(p))
	assert_float(worst).is_less(0.05)  # ~2 % in colour after the square-root curve


func test_colours_normalise_to_the_99th_percentile() -> void:
	var pts := PackedVector2Array()
	for i in 400:
		pts.append(Vector2(i * 8.0, 0))
	for i in 50:
		pts.append(Vector2(1000, 400))  # one very hot spot
	var grid := PlaytraceDensityGrid.build(_sets(Array(pts)), 8.0)
	assert_float(grid.norm_value).is_less(grid.max_value * 0.5)
	var img := PlaytraceHeatmapPalette.colorize(grid, PlaytraceHeatmapPalette.MAGMA)
	var line := grid.cell_of(Vector2(1600, 0))
	assert_float(img.get_pixel(line.x, line.y).a).is_greater(0.5)  # the ordinary path stays visible
