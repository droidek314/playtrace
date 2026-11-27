extends SceneTree
## Generates synthetic sessions with planted problems (contract 6.5).
##
## Usage:
## [codeblock]
## godot --headless --script tools/generate_sessions.gd -- --seed 1 --count 200 \
##     --level res://demo/sandbox.tscn --out user://playtrace/sessions
## [/codeblock]
## Phase 0 stub: implemented in M2 (WS-B).


func _init() -> void:
	push_warning("Playtrace: generate_sessions is not implemented yet (M2).")
	quit(1)
