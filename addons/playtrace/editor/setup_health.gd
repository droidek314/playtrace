@tool
class_name PlaytraceSetupHealth
extends RefCounted
## Setup health (spec 2.3, D-029): what the recorder detected, whether the sessions confirm it, and the
## three warnings, all derived from the session records of [PlaytraceSessionLibrary].
##
## Warning rules (D-029):
## - [code]player_not_found[/code]: a session's header has [code]detection.player == ""[/code] or lists it;
## - [code]player_never_moved[/code]: a player was found, but all its [code]pos[/code] events are within 2 px
##   of the first;
## - [code]reloads_without_deaths[/code]: for some level, re-entries (a [code]level_enter[/code] for a level
##   the session already entered) summed across sessions are 3 or more, and that level has 0 deaths.
## Each code is listed at most once.

## The calls of the manual checklist: the API call, a snippet, where it goes, and the event type that
## proves it works (the item ticks itself when a recorded session contains that type).
const CHECKLIST: Array[Dictionary] = [
	{
		"call": "track()",
		"code": "Playtrace.track(self)",
		"where": "Your player script, in _ready().",
		"event": PlaytraceSchema.POS,
	},
	{
		"call": "death()",
		"code": 'Playtrace.death("spikes")',
		"where": "Where your game kills the player, before it respawns.",
		"event": PlaytraceSchema.DEATH,
	},
	{
		"call": "level()",
		"code": 'Playtrace.level("level_1")',
		"where": "Where a level starts (each scene change, or each area of a big scene).",
		"event": PlaytraceSchema.LEVEL_ENTER,
	},
	{
		"call": "checkpoint()",
		"code": 'Playtrace.checkpoint("before_boss")',
		"where": "Where the player reaches a checkpoint.",
		"event": PlaytraceSchema.CHECKPOINT,
	},
	{
		"call": "complete()",
		"code": "Playtrace.complete()",
		"where": "Where the player finishes the level.",
		"event": PlaytraceSchema.LEVEL_COMPLETE,
	},
	{
		"call": "event()",
		"code": 'Playtrace.event(&"opened_door", {"door": "red"})',
		"where": "Anywhere something worth counting happens.",
		"event": PlaytraceSchema.CUSTOM,
	},
]

## Fix for each warning code: what to write and where.
const FIXES := {
	PlaytraceSchema.WARN_PLAYER_NOT_FOUND:
	{
		"text": 'No player was found. Add your player node to group "player" (Node > Groups), or:',
		"code": "Playtrace.track(self)",
		"where": "Your player script, in _ready().",
	},
	PlaytraceSchema.WARN_PLAYER_NEVER_MOVED:
	{
		"text": "The tracked node never moved, so it is probably the wrong node. Track the node that moves:",
		"code": "Playtrace.track(self)",
		"where": "The script of the node that actually moves, in _ready().",
	},
	PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS:
	{
		"text": "Levels restart often but no deaths were recorded. Report deaths yourself:",
		"code": 'Playtrace.death("spikes")',
		"where": "Where your game kills the player, before it respawns.",
	},
}


## The warning codes the [param records] trigger, each once, in a fixed order.
static func warnings(records: Array[Dictionary]) -> Array[String]:
	var not_found := false
	var never_moved := false
	var reentries := {}
	var deaths := {}
	for r: Dictionary in records:
		var h: Dictionary = r.health
		not_found = not_found or not h.player_found
		never_moved = never_moved or h.never_moved
		for level: String in h.levels:
			reentries[level] = reentries.get(level, 0) + h.levels[level][0]
			deaths[level] = deaths.get(level, 0) + h.levels[level][1]
	var out: Array[String] = []
	if not_found:
		out.append(PlaytraceSchema.WARN_PLAYER_NOT_FOUND)
	if never_moved:
		out.append(PlaytraceSchema.WARN_PLAYER_NEVER_MOVED)
	for level: String in reentries:
		if reentries[level] >= 3 and deaths[level] == 0:
			out.append(PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS)
			break
	return out


## The Setup health card lines: [code]{label, value, ok, warning}[/code]. [code]ok[/code] is true when the
## sessions confirm the detection (green), false when it is only guessed or looks wrong (yellow);
## [code]warning[/code] is the code whose fix applies, or "".
static func card(records: Array[Dictionary]) -> Array[Dictionary]:
	if records.is_empty():
		return []
	var latest: Dictionary = records[-1].health
	var codes := warnings(records)
	var any_death := false
	var any_level := false
	for r: Dictionary in records:
		any_death = any_death or (r.health.types as Array).has(PlaytraceSchema.DEATH)
		any_level = any_level or (r.health.types as Array).has(PlaytraceSchema.LEVEL_ENTER)
	var player_code := ""
	if codes.has(PlaytraceSchema.WARN_PLAYER_NOT_FOUND):
		player_code = PlaytraceSchema.WARN_PLAYER_NOT_FOUND
	elif codes.has(PlaytraceSchema.WARN_PLAYER_NEVER_MOVED):
		player_code = PlaytraceSchema.WARN_PLAYER_NEVER_MOVED
	var deaths_code := (
		PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS if codes.has(PlaytraceSchema.WARN_RELOADS_WITHOUT_DEATHS) else ""
	)
	var player: String = latest.player if not latest.player.is_empty() else "not found"
	var deaths_value: String = latest.deaths_method if any_death else latest.deaths_method + " (no deaths recorded yet)"
	return [
		{"label": "Mode", "value": latest.mode, "ok": true, "warning": ""},
		{"label": "Player", "value": player, "ok": player_code.is_empty(), "warning": player_code},
		{"label": "Deaths", "value": deaths_value, "ok": any_death and deaths_code.is_empty(), "warning": deaths_code},
		{"label": "Levels", "value": latest.levels_method, "ok": any_level, "warning": ""},
	]


## Event types seen in any of [param records] (ticks the manual checklist).
static func seen_types(records: Array[Dictionary]) -> Dictionary:
	var seen := {}
	for r: Dictionary in records:
		for t: String in r.health.types:
			seen[t] = true
	return seen
