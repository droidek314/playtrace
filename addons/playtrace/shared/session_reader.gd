class_name PlaytraceSessionReader
extends RefCounted
## Reads session files (contract 6.2). Never throws: bad lines are skipped with a warning.
##
## Phase 0 stub: implemented in M2 (WS-B).


## Reads one session file. Corrupt lines and unknown types are skipped.
static func read_file(_path: String) -> PlaytraceSession:
	return PlaytraceSession.new()


## Returns the paths of all session files in [param dir].
static func list_sessions(_dir: String = PlaytraceSchema.SESSIONS_DIR) -> Array[String]:
	return []
