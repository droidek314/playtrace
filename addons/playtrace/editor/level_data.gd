@tool
class_name PlaytraceLevelData
extends RefCounted
## Positions and deaths recorded inside one level, gathered from many sessions.
##
## Only events between a [code]level_enter[/code] for [member level] and the next
## [code]level_enter[/code]/[code]level_exit[/code] count, so a session that visits several levels
## contributes only its part in this one. The overlay compares [member level] with the edited
## scene's [code]scene_file_path[/code]. Safe to build on a worker thread.

## Level id these points belong to (a scene path in plug-and-play mode).
var level := ""
## Movement samples ([code]pos[/code] events), one array per session that entered the level.
var paths: Array[PackedVector2Array] = []
## Death positions from all sessions.
var deaths := PackedVector2Array()
## Number of sessions that entered the level.
var session_count := 0
## Smallest rect holding every movement sample (lets the density grid skip a pass over the points).
var bounds := Rect2()

var _has_bounds := false


func _init(level_id: String = "") -> void:
	level = level_id


## Adds the part of one session's [param events] (contract 6.2 event dictionaries) played in [member level].
func add_session(events: Array) -> void:
	var inside := false
	var entered := false
	var pts := PackedVector2Array()
	for e: Variant in events:
		if not e is Dictionary:
			continue
		var type: Variant = e.get("type")
		if type == PlaytraceSchema.LEVEL_ENTER:
			inside = e.get("level") == level
			entered = entered or inside
		elif type == PlaytraceSchema.LEVEL_EXIT:
			inside = false
		elif inside and (type == PlaytraceSchema.POS or type == PlaytraceSchema.DEATH):
			var p: Variant = e.get("p")
			if not p is Array or p.size() < 2 or not _is_number(p[0]) or not _is_number(p[1]):
				continue
			if type == PlaytraceSchema.POS:
				var v := Vector2(p[0], p[1])
				bounds = bounds.expand(v) if _has_bounds else Rect2(v, Vector2.ZERO)
				_has_bounds = true
				pts.append(v)
			else:
				deaths.append(Vector2(p[0], p[1]))
	if entered:
		session_count += 1
		paths.append(pts)


## Reads every [code].jsonl[/code] file in [param dirs] and keeps what was played in [param level_id].
static func load_dirs(dirs: Array[String], level_id: String) -> PlaytraceLevelData:
	var data := PlaytraceLevelData.new(level_id)
	for dir: String in dirs:
		for path: String in PlaytraceSessionReader.list_sessions(dir):
			var session := PlaytraceSessionReader.read_file(path)
			for w: String in session.warnings:
				push_warning(w)
			data.add_session(session.events)
	return data


static func _is_number(v: Variant) -> bool:
	return v is float or v is int
