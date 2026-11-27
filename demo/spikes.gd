extends Area2D
## Spikes: touching them restarts the level, which Playtrace auto-detects as a death.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		get_tree().reload_current_scene.call_deferred()
