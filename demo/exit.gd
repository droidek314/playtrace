extends Area2D
## Level exit: reports completion to Playtrace (if the autoload exists) and restarts the level.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var playtrace := get_node_or_null(^"/root/Playtrace")
	if playtrace:
		playtrace.complete()
	print("Playtrace demo: level complete")
	get_tree().reload_current_scene.call_deferred()
