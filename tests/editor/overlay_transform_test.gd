extends GdUnitTestSuite
## T20: world -> overlay mapping at zoom 0.25 / 1 / 4 and after pan, for both layers.


func test_world_to_overlay_at_each_zoom() -> void:
	var offset := Vector2(-120, 80)
	var w := Vector2(300, -50)
	for zoom: float in [0.25, 1.0, 4.0]:
		var xf := PlaytraceOverlayTransform.canvas_transform(zoom, offset)
		var expected := (w - offset) * zoom
		assert_vector(PlaytraceOverlayTransform.world_to_overlay(xf, w)).is_equal_approx(expected, Vector2(1e-3, 1e-3))
		# The view offset is the world point at the overlay's top-left corner.
		assert_vector(xf * offset).is_equal_approx(Vector2.ZERO, Vector2(1e-3, 1e-3))


func test_pan_shifts_overlay_by_zoomed_delta() -> void:
	var w := Vector2(64, 400)
	for zoom: float in [0.25, 1.0, 4.0]:
		var before := PlaytraceOverlayTransform.canvas_transform(zoom, Vector2(0, 0))
		var after := PlaytraceOverlayTransform.canvas_transform(zoom, Vector2(50, -30))
		var moved := (after * w) - (before * w)
		assert_vector(moved).is_equal_approx(Vector2(-50, 30) * zoom, Vector2(1e-3, 1e-3))


func test_heatmap_rect_maps_with_zoom() -> void:
	var rect := Rect2(100, 200, 640, 320)
	for zoom: float in [0.25, 1.0, 4.0]:
		var xf := PlaytraceOverlayTransform.canvas_transform(zoom, Vector2(10, 20))
		var r := PlaytraceOverlayTransform.world_rect_to_overlay(xf, rect)
		assert_vector(r.position).is_equal_approx((rect.position - Vector2(10, 20)) * zoom, Vector2(1e-3, 1e-3))
		assert_vector(r.size).is_equal_approx(rect.size * zoom, Vector2(1e-3, 1e-3))


func test_death_marks_centre_on_death_and_keep_screen_size() -> void:
	var deaths := PackedVector2Array([Vector2(912, 388), Vector2(-5, 7)])
	for zoom: float in [0.25, 1.0, 4.0]:
		var xf := PlaytraceOverlayTransform.canvas_transform(zoom, Vector2(300, 100))
		var segs := PlaytraceHeatmapOverlay.death_segments(xf, deaths, 5.0)
		assert_int(segs.size()).is_equal(8)
		for i in deaths.size():
			var centre := (segs[i * 4] + segs[i * 4 + 1]) / 2.0
			assert_vector(centre).is_equal_approx(xf * deaths[i], Vector2(1e-3, 1e-3))
			assert_float(segs[i * 4].distance_to(segs[i * 4 + 1])).is_equal_approx(10.0 * sqrt(2.0), 1e-3)
