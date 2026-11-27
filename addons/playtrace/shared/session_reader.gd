class_name PlaytraceSessionReader
extends RefCounted
## Reads session files (contract 6.2). Never throws: bad lines are skipped with a warning.
##
## Forward compatible: events with an unknown "type" and unknown fields are ignored silently.
## Lines that are not a JSON object, or lack a numeric "t" / String "type", count as corrupt;
## all corrupt lines in one file produce a single warning.

## Event types this reader understands; others are skipped.
const KNOWN_TYPES: Array[String] = [
	PlaytraceSchema.LEVEL_ENTER,
	PlaytraceSchema.LEVEL_EXIT,
	PlaytraceSchema.POS,
	PlaytraceSchema.DEATH,
	PlaytraceSchema.STUCK,
	PlaytraceSchema.CHECKPOINT,
	PlaytraceSchema.LEVEL_COMPLETE,
	PlaytraceSchema.QUIT,
	PlaytraceSchema.CUSTOM,
	PlaytraceSchema.FEEDBACK,
]


## Reads one session file. Corrupt lines and unknown types are skipped; problems go to warnings.
static func read_file(path: String) -> PlaytraceSession:
	var session := PlaytraceSession.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		session.warnings.append("Playtrace: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return session
	var corrupt := 0
	var json := JSON.new()  # JSON.parse() does not log engine errors, unlike JSON.parse_string()
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		if json.parse(line) != OK or not json.data is Dictionary:
			corrupt += 1
			continue
		var d: Dictionary = json.data
		var type: Variant = d.get("type")
		if session.header.is_empty() and session.events.is_empty() and type == PlaytraceSchema.SESSION_START:
			session.header = d
			continue
		if not type is String or not (d.get("t") is float or d.get("t") is int):
			corrupt += 1
			continue
		if not KNOWN_TYPES.has(type):
			continue
		d["t"] = int(d["t"])
		session.events.append(d)
	if session.header.is_empty():
		session.warnings.append("Playtrace: %s has no session_start header" % path)
	if corrupt > 0:
		session.warnings.append("Playtrace: skipped %d corrupt line(s) in %s" % [corrupt, path])
	return session


## Returns the full paths of all .jsonl session files in [param dir], sorted by name.
static func list_sessions(dir: String = PlaytraceSchema.SESSIONS_DIR) -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f: String in files:
		if f.ends_with(".jsonl"):
			result.append(dir.path_join(f))
	return result
