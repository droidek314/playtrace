extends GdUnitTestSuite
## Settings registration (contract 6.3): defaults are registered and existing values are kept.


func after_test() -> void:
	ProjectSettings.clear(PlaytraceSettings.STUCK_SECONDS)


func test_register_defaults_adds_missing_keys() -> void:
	ProjectSettings.clear(PlaytraceSettings.STUCK_SECONDS)
	PlaytraceSettings.register_defaults()
	assert_float(ProjectSettings.get_setting(PlaytraceSettings.STUCK_SECONDS)).is_equal(8.0)


func test_register_defaults_keeps_existing_values() -> void:
	ProjectSettings.set_setting(PlaytraceSettings.STUCK_SECONDS, 3.0)
	PlaytraceSettings.register_defaults()
	assert_float(PlaytraceSettings.get_value(PlaytraceSettings.STUCK_SECONDS)).is_equal(3.0)
