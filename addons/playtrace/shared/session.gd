class_name PlaytraceSession
extends RefCounted
## One recorded session, as read from a session file (contract 6.2).
##
## Produced by [PlaytraceSessionReader]. Holds the header line, the events in file order
## and any warnings from reading. Helpers answer the questions the editor asks most.

## The session_start header line. Empty if the file had no valid header.
var header: Dictionary = {}
## All known events after the header, in file order. Every event has an int "t" and a String "type".
var events: Array[Dictionary] = []
## Problems found while reading (corrupt lines, missing header). At most one per kind.
var warnings: Array[String] = []


## Returns the events whose "type" equals [param type], in file order.
func events_of_type(type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			result.append(e)
	return result


## Returns the level ids entered in this session, in order of first entry, without duplicates.
func levels() -> Array[String]:
	var result: Array[String] = []
	for e: Dictionary in events:
		if e["type"] == PlaytraceSchema.LEVEL_ENTER:
			var id := str(e.get("level", ""))
			if not id.is_empty() and not result.has(id):
				result.append(id)
	return result


## Returns the session length in milliseconds: the largest event "t".
func duration_ms() -> int:
	var result := 0
	for e: Dictionary in events:
		result = maxi(result, e["t"])
	return result


## Returns "completed" or "quit" from whichever of level_complete / quit came last, else "unknown".
func outcome() -> String:
	for i in range(events.size() - 1, -1, -1):
		match events[i]["type"]:
			PlaytraceSchema.LEVEL_COMPLETE:
				return "completed"
			PlaytraceSchema.QUIT:
				return "quit"
	return "unknown"
