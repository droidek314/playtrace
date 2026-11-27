extends GdUnitTestSuite
## Smoke test for demo/sandbox.tscn: it loads, the player is in group "player" and lands on the ground.


func test_sandbox_player_lands_on_ground() -> void:
	var runner := scene_runner("res://demo/sandbox.tscn")
	var player: CharacterBody2D = runner.find_child("Player")
	assert_bool(player.is_in_group("player")).is_true()
	await runner.simulate_frames(60)
	assert_float(player.position.y).is_equal_approx(432.0, 1.0)
	assert_float(player.position.x).is_equal_approx(64.0, 1.0)
