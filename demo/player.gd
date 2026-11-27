extends CharacterBody2D
## Minimal platformer player for the sandbox level: arrows/A-D to move, Space/Up to jump.
##
## Contains no Playtrace code on purpose: the sandbox shows plug-and-play detection.

const SPEED := 220.0
const JUMP_VELOCITY := -420.0
const FALL_LIMIT_Y := 900.0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta: float) -> void:
	velocity.y += _gravity * delta
	if is_on_floor() and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")):
		velocity.y = JUMP_VELOCITY
	velocity.x = Input.get_axis("ui_left", "ui_right") * SPEED
	move_and_slide()
	if position.y > FALL_LIMIT_Y:
		get_tree().reload_current_scene.call_deferred()
