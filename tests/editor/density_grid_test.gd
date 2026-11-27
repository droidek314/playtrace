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
