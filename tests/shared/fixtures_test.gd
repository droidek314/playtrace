extends GdUnitTestSuite
## Checks the frozen fixtures stay as documented in tests/fixtures/README.md.

const FIXTURES := "res://tests/fixtures/"


func _bad_lines(file_name: String) -> int:
	var bad := 0
	for line: String in FileAccess.get_file_as_string(FIXTURES + file_name).split("\n", false):
		var json := JSON.new()  # JSON.parse() does not log engine errors, unlike JSON.parse_string()
		if json.parse(line) != OK or not json.data is Dictionary:
			bad += 1
	return bad


func test_valid_fixtures_have_no_bad_lines() -> void:
	for f: String in ["completed.jsonl", "quit.jsonl", "many_deaths.jsonl", "stuck.jsonl", "with_feedback.jsonl"]:
		assert_int(_bad_lines(f)).override_failure_message(f).is_equal(0)


func test_corrupt_fixture_has_four_bad_lines() -> void:
	assert_int(_bad_lines("corrupt.jsonl")).is_equal(4)
