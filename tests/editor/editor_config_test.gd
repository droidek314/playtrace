extends GdUnitTestSuite
## T25: layer and dock settings survive a save and a fresh load (as when the plugin is reloaded).

const PATH := "user://playtrace_tests/editor_config_test.cfg"


func after() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_defaults_without_a_file() -> void:
	var cfg := PlaytraceEditorConfig.new("user://playtrace_tests/missing.cfg")
	assert_float(cfg.get_value("layers/opacity")).is_equal(0.65)
	assert_float(cfg.get_value("layers/radius_px")).is_equal(16.0)
	assert_bool(cfg.get_value("setup/wizard_done")).is_false()
	assert_dict(cfg.filter()).is_equal(PlaytraceSessionLibrary.NO_FILTER)


func test_round_trip() -> void:
	var cfg := PlaytraceEditorConfig.new(PATH)
	cfg.set_value("layers/opacity", 0.4)
	cfg.set_value("layers/palette", PlaytraceHeatmapPalette.VIRIDIS)
	cfg.set_value("layers/stuck", false)
	cfg.set_value("layers/radius_px", 30.0)
	cfg.set_value("filters/outcome", "quit")
	cfg.set_value("dock/tab", 2)
	cfg.save()
	var again := PlaytraceEditorConfig.new(PATH)
	assert_float(again.get_value("layers/opacity")).is_equal(0.4)
	assert_int(again.get_value("layers/palette")).is_equal(PlaytraceHeatmapPalette.VIRIDIS)
	assert_bool(again.get_value("layers/stuck")).is_false()
	assert_float(again.get_value("layers/radius_px")).is_equal(30.0)
	assert_str(again.filter().outcome).is_equal("quit")
	assert_int(again.get_value("dock/tab")).is_equal(2)
	assert_bool(again.get_value("layers/deaths")).is_true()  # untouched keys keep their default
