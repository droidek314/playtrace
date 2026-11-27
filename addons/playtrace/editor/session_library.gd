@tool
class_name PlaytraceSessionLibrary
extends RefCounted
## Loads session files once and keeps a small record per session for the dock and the overlay.
##
## A record is a [Dictionary]:
## [codeblock]
## {"summary": {...}, "level": PlaytraceLevelData, "health": {...}}
## [/codeblock]
## - [code]summary[/code]: what the Sessions list shows and filters on (see [method summarize]);
## - [code]level[/code]: the session's part in the level being shown, so changing a filter only merges
##   records ([method combine]) and never re-reads files;
## - [code]health[/code]: facts for the Setup tab ([PlaytraceSetupHealth]).
## The events themselves are dropped after loading, to keep memory small. Safe on a worker thread.

## Filter keys and their "match everything" values.
const NO_FILTER := {"level": "", "build": "", "outcome": "", "date_from": "", "date_to": ""}


## Reads every session file in [param dirs] and returns one record per file, oldest first.
static func load_dirs(dirs: Array[String], level_id: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for dir: String in dirs:
		for path: String in PlaytraceSessionReader.list_sessions(dir):
			var session := PlaytraceSessionReader.read_file(path)
			for w: String in session.warnings:
				push_warning(w)
			records.append(make_record(session, path, level_id))
	records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.summary.started_utc < b.summary.started_utc
	)
	return records


## Builds the record of one [param session] read from [param path], keeping its part in [param level_id].
static func make_record(session: PlaytraceSession, path: String, level_id: String) -> Dictionary:
	var part := PlaytraceLevelData.new(level_id)
	part.add_session(session.events)
	return {"summary": summarize(session, path), "level": part, "health": health_facts(session)}


## The Sessions list row of [param session]: id, path, build, started_utc, date (YYYY-MM-DD),
## duration_ms, deaths (all levels), outcome and levels.
static func summarize(session: PlaytraceSession, path: String) -> Dictionary:
	var started := str(session.header.get("started_utc", ""))
	return {
		"id": str(session.header.get("session", path.get_file().get_basename())),
		"path": path,
		"build": str(session.header.get("build", "")),
		"started_utc": started,
		"date": started.substr(0, 10),
		"duration_ms": session.duration_ms(),
		"deaths": session.events_of_type(PlaytraceSchema.DEATH).size(),
		"outcome": session.outcome(),
		"levels": session.levels(),
	}


## The facts [PlaytraceSetupHealth] needs from one session (rules in D-029).
static func health_facts(session: PlaytraceSession) -> Dictionary:
	var detection: Dictionary = (
		session.header.get("detection", {}) if session.header.get("detection") is Dictionary else {}
	)
	var player := str(detection.get("player", ""))
	var header_warnings: Array = detection.get("warnings", []) if detection.get("warnings") is Array else []
	var types := {}
	var entered := {}
	var levels := {}  # level id -> [re-entries, deaths]
	var current := ""
	var first := Vector2.INF
	var moved := false
	var pos_count := 0
	for e: Dictionary in session.events:
		var type: String = e["type"]
		types[type] = true
		if type == PlaytraceSchema.LEVEL_ENTER:
			current = str(e.get("level", ""))
			if not levels.has(current):
				levels[current] = [0, 0]
			if entered.has(current):
				levels[current][0] += 1
			entered[current] = true
		elif type == PlaytraceSchema.DEATH and levels.has(current):
			levels[current][1] += 1
		elif type == PlaytraceSchema.POS and e.get("p") is Array and e["p"].size() >= 2:
			var v := Vector2(float(e["p"][0]), float(e["p"][1]))
			pos_count += 1
			if first == Vector2.INF:
				first = v
			elif v.distance_to(first) > 2.0:
				moved = true
	var found := not player.is_empty() and not header_warnings.has(PlaytraceSchema.WARN_PLAYER_NOT_FOUND)
	return {
		"mode": str(detection.get("mode", "")),
		"player": player,
		"deaths_method": str(detection.get("deaths", "")),
		"levels_method": str(detection.get("levels", "")),
		"player_found": found,
		"never_moved": found and pos_count > 0 and not moved,
		"levels": levels,
		"types": types.keys(),
	}


## True when [param summary] passes [param filter] (keys of [constant NO_FILTER]; empty = any).
## Dates compare as YYYY-MM-DD strings, both ends inclusive.
static func matches(summary: Dictionary, filter: Dictionary) -> bool:
	var level: String = filter.get("level", "")
	if not level.is_empty() and not (summary.levels as Array).has(level):
		return false
	var build: String = filter.get("build", "")
	if not build.is_empty() and summary.build != build:
		return false
	var outcome: String = filter.get("outcome", "")
	if not outcome.is_empty() and summary.outcome != outcome:
		return false
	var from: String = filter.get("date_from", "")
	if not from.is_empty() and summary.date < from:
		return false
	var to: String = filter.get("date_to", "")
	if not to.is_empty() and summary.date > to:
		return false
	return true


## The records of [param records] that pass filter [param by].
static func filter(records: Array[Dictionary], by: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in records:
		if matches(r.summary, by):
			out.append(r)
	return out


## Merges the level parts of [param records] into one [PlaytraceLevelData] for [param level_id].
static func combine(records: Array[Dictionary], level_id: String) -> PlaytraceLevelData:
	var data := PlaytraceLevelData.new(level_id)
	for r: Dictionary in records:
		data.merge(r.level)
	return data


## Distinct values of summary [param key] over [param records], sorted (for the filter menus).
static func values_of(records: Array[Dictionary], key: String) -> Array[String]:
	var seen := {}
	for r: Dictionary in records:
		var v: Variant = r.summary[key]
		for item: Variant in v if v is Array else [v]:
			if not str(item).is_empty():
				seen[str(item)] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	out.sort()
	return out
