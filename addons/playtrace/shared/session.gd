class_name PlaytraceSession
extends RefCounted
## One recorded session, as read from a session file (contract 6.2).
##
## Produced by [PlaytraceSessionReader]. Phase 0 stub: helpers are implemented in M2 (WS-B).

## The session_start header line.
var header: Dictionary = {}
## All events after the header, in file order.
var events: Array[Dictionary] = []
## Problems found while reading (corrupt lines and similar).
var warnings: Array[String] = []


## Returns the events whose "type" equals [param type].
func events_of_type(_type: String) -> Array[Dictionary]:
	return []


## Returns the level ids entered in this session, in order of first entry.
func levels() -> Array[String]:
	return []


## Returns the session length in milliseconds (the last event's t).
func duration_ms() -> int:
	return 0


## Returns "completed", "quit" or "unknown".
func outcome() -> String:
	return "unknown"
