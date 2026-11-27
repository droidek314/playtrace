extends GdUnitTestSuite
## T23: with a fixed seed the Insights list finds what tools/planted.json planted:
## the top death hotspot, the largest stuck zone, the most common quit point and the hidden room's floor.

const DIR := "user://playtrace_tests/insights_seed_7"

var _gen := PlaytraceSessionGenerator.new()
var _planted: Dictionary = _gen.planted()
var _insights: Array[Dictionary] = []


func before() -> void:
	var level: String = _planted["level"]
	for f: String in PlaytraceSessionReader.list_sessions(DIR):
		DirAccess.remove_absolute(f)
	_gen.write(7, 200, level, DIR)
	var records := PlaytraceSessionLibrary.load_dirs([DIR] as Array[String], level)
	for f: String in PlaytraceSessionReader.list_sessions(DIR):
		DirAccess.remove_absolute(f)
	var data := PlaytraceSessionLibrary.combine(records, level)
	var grid := PlaytraceDensityGrid.build_level(data, 16.0)
	var scene: Node = load(level).instantiate()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(scene)
	var floors := PlaytraceLevelSurfaces.from_scene(scene)
	scene.free()
	_insights = PlaytraceInsights.compute(data, grid, floors)


func _first(kind: String) -> Dictionary:
	for i: Dictionary in _insights:
		if i.kind == kind:
			return i
	return {}


func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func test_top_death_hotspot_is_the_planted_cluster() -> void:
	var top := _first("death")
	assert_float((top.pos as Vector2).distance_to(_v(_planted["death_cluster"]["center"]))).is_less(32.0)
	assert_str(top.title).contains("of players died here")
	assert_int(top.count).is_greater(100)
	assert_object(_insights[0]).is_equal(top)  # death hotspots come first


func test_largest_stuck_zone_and_quit_point() -> void:
	var stuck := _first("stuck")
	assert_float((stuck.pos as Vector2).distance_to(_v(_planted["stuck_zone"]["center"]))).is_less(32.0)
	var quit := _first("quit")
	assert_float((quit.pos as Vector2).distance_to(_v(_planted["quit_point"]["center"]))).is_less(32.0)
	assert_str(quit.title).starts_with("Most common quit point")


func test_hidden_room_floor_is_never_visited() -> void:
	var r: Array = _planted["unvisited_area"]["rect"]
	var planted := Rect2(r[0], r[1], r[2], r[3])
	var hit := false
	for i: Dictionary in _insights:
		if i.kind == "unvisited":
			hit = hit or (i.rect as Rect2).intersects(planted)
			# Nothing on the walked route counts as unvisited.
			assert_bool((i.rect as Rect2).intersects(Rect2(64, 400, 1900, 48))).is_false()
	assert_bool(hit).is_true()


func test_ranking_is_stable() -> void:
	var kinds: Array = _insights.map(func(i: Dictionary) -> String: return i.kind)
	assert_str(kinds[0]).is_equal("death")
	assert_bool(kinds.has("stuck") and kinds.has("quit") and kinds.has("unvisited")).is_true()
	assert_int(kinds.find("stuck")).is_less(kinds.find("quit"))
