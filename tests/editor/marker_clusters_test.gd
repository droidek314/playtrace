extends GdUnitTestSuite
## T24: merged badge count = sum of merged markers; clusters split again when zoomed in.


func _random_points(n: int, seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in n:
		# A few tight groups plus scattered noise.
		var centre := Vector2(200 * (i % 5), 100 * (i % 3))
		pts.append(
			(
				centre + Vector2(rng.randfn(0, 6), rng.randfn(0, 6))
				if i % 4
				else Vector2(rng.randf() * 1000, rng.randf() * 400)
			)
		)
	return pts


func test_badge_counts_sum_to_marker_count() -> void:
	var pts := _random_points(500, 3)
	for cell: float in [4.0, 16.0, 56.0, 224.0, 900.0]:  # zoom 4 ... 0.0625 with a 14 px badge
		var clusters := PlaytraceMarkerClusters.cluster(pts, cell)
		var total := 0
		var seen := {}
		for c: Dictionary in clusters:
			total += c.count
			assert_int(c.members.size()).is_equal(c.count)
			for i: int in c.members:
				assert_bool(seen.has(i)).is_false()
				seen[i] = true
		assert_int(total).is_equal(pts.size())


func test_zoomed_out_merges_and_zoomed_in_splits() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(0, 5), Vector2(300, 0)])
	var far := PlaytraceMarkerClusters.cluster(pts, 40.0)
	assert_int(far.size()).is_equal(2)
	assert_int(far[0].count).is_equal(3)
	assert_vector(far[0].pos).is_equal_approx(Vector2(5.0 / 3.0, 5.0 / 3.0), Vector2(0.01, 0.01))
	assert_int(PlaytraceMarkerClusters.cluster(pts, 2.0).size()).is_equal(4)


func test_group_on_a_cell_border_is_not_split() -> void:
	var pts := PackedVector2Array([Vector2(39, 10), Vector2(41, 10)])
	assert_int(PlaytraceMarkerClusters.cluster(pts, 40.0).size()).is_equal(1)


func test_weights_add_up() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(500, 0)])
	var clusters := PlaytraceMarkerClusters.cluster(pts, 40.0, PackedFloat64Array([8.0, 12.5, 9.0]))
	assert_float(clusters[0].weight).is_equal_approx(20.5, 0.001)
