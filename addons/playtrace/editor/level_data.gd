@tool
class_name PlaytraceLevelData
extends RefCounted
## Positions and deaths recorded inside one level, gathered from many sessions.
##
## Only events between a [code]level_enter[/code] for [member level] and the next
## [code]level_enter[/code]/[code]level_exit[/code] count, so a session that visits several levels
## contributes only its part in this one. The overlay compares [member level] with the edited
## scene's [code]scene_file_path[/code]. Safe to build on a worker thread.
##
## Movement is kept as time, not as sample counts, because the recorder writes a [code]pos[/code] only
## after the player moved (contract 5): a long gap between samples is time spent standing still.
## For consecutive samples a -> b with dt seconds, up to [constant MOVE_SAMPLE_S] is travel time along
## a -> b ([member path_travel_s]); the rest is a stay at a ([member stay_points]). The last sample of a
## path stays until the path ended. So every path adds exactly its duration to the heatmap.

## Steps faster than this (px/s) are teleports (respawn, door, scripted move): the path is cut there.
const TELEPORT_PX_S := 1500.0
## Longest gap between samples counted as travel: the default pos interval (contract 6.3).
const MOVE_SAMPLE_S := 0.2

## Level id these points belong to (a scene path in plug-and-play mode).
var level := ""
## Movement paths: unbroken runs of [code]pos[/code] samples, several per session.
var paths: Array[PackedVector2Array] = []
## For each path, its travel time in seconds (spread along the path by [PlaytraceDensityGrid]).
var path_travel_s := PackedFloat64Array()
## For each path, its length in world pixels (sets how finely the grid subdivides it).
var path_length_px := PackedFloat64Array()
## For each path, true when it runs more along x than along y (the grid splats along that axis).
var path_horizontal: Array[bool] = []
## Points where players stood still, with the seconds in [member stay_seconds].
var stay_points := PackedVector2Array()
## Seconds spent at each of [member stay_points].
var stay_seconds := PackedFloat64Array()
## Death positions from all sessions.
var deaths := PackedVector2Array()
## For each death, the index of its session (0 .. [member session_count] - 1).
var death_session := PackedInt32Array()
## Positions of [code]stuck[/code] events.
var stuck_points := PackedVector2Array()
## Seconds of each stuck event ([code]data.seconds[/code]).
var stuck_seconds := PackedFloat64Array()
## For each stuck event, the index of its session.
var stuck_session := PackedInt32Array()
## Positions of [code]quit[/code] events.
var quit_points := PackedVector2Array()
## For each quit, the index of its session.
var quit_session := PackedInt32Array()
## Number of sessions that entered the level.
var session_count := 0
## Smallest rect holding every movement sample (lets the density grid skip a pass over the points).
var bounds := Rect2()

var _has_bounds := false
var _pts := PackedVector2Array()
var _ts := PackedFloat64Array()


func _init(level_id: String = "") -> void:
	level = level_id


## Adds the part of one session's [param events] (contract 6.2 event dictionaries) played in [member level].
## Path rules: a path is broken (never joined across) at [code]death[/code], [code]level_enter[/code],
## [code]level_exit[/code], and at any step faster than [constant TELEPORT_PX_S]. A path ends at the time of
## the event that broke it; a path still open when the session ends, at the session's last event in the
## level (so the hesitation before a [code]quit[/code] counts). Other events are not part of the path.
func add_session(events: Array) -> void:
	var index := session_count
	var inside := false
	var entered := false
	var last_t := 0.0
	for e: Variant in events:
		if not e is Dictionary:
			continue
		var type: Variant = e.get("type")
		var t := float(e.get("t", 0)) / 1000.0
		if type == PlaytraceSchema.LEVEL_ENTER or type == PlaytraceSchema.LEVEL_EXIT or type == PlaytraceSchema.DEATH:
			if inside:
				_end_path(t)
			if type == PlaytraceSchema.LEVEL_ENTER:
				inside = e.get("level") == level
				entered = entered or inside
			elif type == PlaytraceSchema.LEVEL_EXIT:
				inside = false
		if not inside:
			continue
		last_t = t
		if (
			type != PlaytraceSchema.POS
			and type != PlaytraceSchema.DEATH
			and type != PlaytraceSchema.STUCK
			and type != PlaytraceSchema.QUIT
		):
			continue
		var p: Variant = e.get("p")
		if not p is Array or p.size() < 2 or not _is_number(p[0]) or not _is_number(p[1]):
			continue
		var v := Vector2(p[0], p[1])
		if type == PlaytraceSchema.DEATH:
			deaths.append(v)
			death_session.append(index)
			continue
		if type == PlaytraceSchema.STUCK:
			var data: Variant = e.get("data")
			var secs: Variant = data.get("seconds") if data is Dictionary else null
			stuck_points.append(v)
			stuck_seconds.append(float(secs) if _is_number(secs) else 0.0)
			stuck_session.append(index)
			continue
		if type == PlaytraceSchema.QUIT:
			quit_points.append(v)
			quit_session.append(index)
			continue
		if not _pts.is_empty() and _pts[-1].distance_to(v) > TELEPORT_PX_S * (t - _ts[-1]):
			_end_path(t)  # teleport: the time before the jump was spent at the last sample
		_pts.append(v)
		_ts.append(t)
	if inside:
		_end_path(last_t)
	if entered:
		session_count += 1


## Adds one unbroken path: [param points] with their [param times] in seconds, plus one extra time at the
## end, when the path ended ([code]times.size() == points.size() + 1[/code]).
func add_path(points: PackedVector2Array, times: PackedFloat64Array) -> void:
	if points.is_empty() or times.size() != points.size() + 1:
		return
	var travel := 0.0
	var length := 0.0
	var along := Vector2.ZERO
	for i in points.size():
		var v := points[i]
		bounds = bounds.expand(v) if _has_bounds else Rect2(v, Vector2.ZERO)
		_has_bounds = true
		var dt := times[i + 1] - times[i]
		if i + 1 < points.size():
			length += v.distance_to(points[i + 1])
			along += (points[i + 1] - v).abs()
			var move := minf(dt, MOVE_SAMPLE_S)
			travel += move
			dt -= move
		if dt > 0.0:
			stay_points.append(v)
			stay_seconds.append(dt)
	paths.append(points)
	path_travel_s.append(travel)
	path_length_px.append(length)
	path_horizontal.append(along.x >= along.y)


## Appends everything of [param other] (for example one session's part) as the next sessions of this data.
func merge(other: PlaytraceLevelData) -> void:
	var base := session_count
	paths.append_array(other.paths)
	path_travel_s.append_array(other.path_travel_s)
	path_length_px.append_array(other.path_length_px)
	path_horizontal.append_array(other.path_horizontal)
	stay_points.append_array(other.stay_points)
	stay_seconds.append_array(other.stay_seconds)
	deaths.append_array(other.deaths)
	death_session.append_array(_shifted(other.death_session, base))
	stuck_points.append_array(other.stuck_points)
	stuck_seconds.append_array(other.stuck_seconds)
	stuck_session.append_array(_shifted(other.stuck_session, base))
	quit_points.append_array(other.quit_points)
	quit_session.append_array(_shifted(other.quit_session, base))
	session_count += other.session_count
	if other._has_bounds:
		bounds = bounds.merge(other.bounds) if _has_bounds else other.bounds
		_has_bounds = true


static func _shifted(indices: PackedInt32Array, by: int) -> PackedInt32Array:
	var out := indices.duplicate()
	for i in out.size():
		out[i] += by
	return out


# Closes the open path at time end_t (never before its last sample) and starts a new one.
func _end_path(end_t: float) -> void:
	if _pts.is_empty():
		return
	_ts.append(maxf(end_t, _ts[-1]))
	add_path(_pts, _ts)
	_pts = PackedVector2Array()
	_ts = PackedFloat64Array()


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
