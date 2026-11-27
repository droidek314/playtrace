extends Node
## The [code]Playtrace[/code] autoload: records playtest sessions from a running game.
##
## In plug-and-play mode it finds the player, levels, deaths, stuck moments and quits on its own.
## The methods below are the manual API (contract 6.1). The first explicit call for a feature
## turns off auto-detection of that feature for the rest of the run (takeover rule).
## All methods are safe no-ops when recording is off.
## No [code]class_name[/code]: it would clash with the autoload name (D-006).
## Phase 0 stub: bodies are implemented in M1 (WS-A).

## Emitted when a new session file has been started.
signal session_started(session_id: String)
## Emitted when a session has been finished and its file fully written to [param path].
signal session_finished(session_id: String, path: String)


## Tracks [param node] as the player; disables auto player detection.
func track(_node: Node2D) -> void:
	pass


## Records a death at the player's position; disables auto deaths. Empty cause is written as "manual".
func death(_cause: String = "") -> void:
	pass


## Sets the current level id; disables auto level detection.
func level(_id: String) -> void:
	pass


## Records a custom event with a name and optional data.
func event(_name: StringName, _data: Dictionary = {}) -> void:
	pass


## Records reaching a checkpoint at the player's position.
func checkpoint(_name: String) -> void:
	pass


## Records that the current level was completed.
func complete() -> void:
	pass


## Returns true while a session is being recorded.
func is_recording() -> bool:
	return false


## Returns the detection report: same shape as the header's detection plus "warnings": Array[String].
func get_detection_report() -> Dictionary:
	return {}
