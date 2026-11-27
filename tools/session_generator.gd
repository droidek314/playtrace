class_name PlaytraceSessionGenerator
extends RefCounted
## Builds synthetic session files with known problems planted at fixed positions (contract 6.5).
##
## Ground truth lives in tools/planted.json; tests assert the editor finds what is planted here.
## Every session walks the sandbox route from spawn to exit along the ground (y = 432) and,
## driven by a seeded RNG, may:
## - die 1-4 times at the spikes (death_cluster), respawning at spawn each time;
## - climb the dead-end branch and walk back (backtrack_loop), sometimes getting stuck at its end
##   (stuck_zone) for 8-15 s;
## - quit at the hard step (quit_point) instead of finishing.
## Nobody ever enters unvisited_area. The output depends only on the seed: no clock, no engine
## version, fixed key order, so the same seed gives byte-identical files.

const PLANTED_PATH := "res://tools/planted.json"
const WALK_SPEED_PX_S := 200.0
const SAMPLE_MS := 200
const GROUND_Y := 432.0
const BASE_UNIX := 1796083200  # 2026-12-01T00:00:00Z

var _rng := RandomNumberGenerator.new()
var _planted: Dictionary
var _lines: PackedStringArray
var _t := 0
var _pos := Vector2.ZERO


func _init() -> void:
	_planted = JSON.parse_string(FileAccess.get_file_as_string(PLANTED_PATH))


## Returns the planted ground truth from tools/planted.json.
func planted() -> Dictionary:
	return _planted


## Generates [param count] sessions for [param level]. Returns session id -> file text.
func generate(seed_value: int, count: int, level: String) -> Dictionary:
	_rng.seed = seed_value
	var result := {}
	for i in count:
		var id := _uuid()
		result[id] = _session(id, i, level)
	return result


## Generates sessions and writes them as <id>.jsonl into [param out_dir]. Returns the number written.
func write(seed_value: int, count: int, level: String, out_dir: String) -> int:
	var abs_dir := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var sessions := generate(seed_value, count, level)
	for id: String in sessions:
		var f := FileAccess.open(abs_dir.path_join(id + ".jsonl"), FileAccess.WRITE)
		if f == null:
			push_warning("Playtrace: cannot write to %s" % abs_dir)
			return 0
		f.store_string(sessions[id])
	return sessions.size()


func _session(id: String, index: int, level: String) -> String:
	_lines = PackedStringArray()
	_t = 0
	_pos = _v(_planted["spawn"])
	var started := Time.get_datetime_string_from_unix_time(BASE_UNIX + index * 600) + "Z"
	_emit(
		{
			"schema": PlaytraceSchema.VERSION,
			"type": PlaytraceSchema.SESSION_START,
			"session": id,
			"game": "playtrace-demo",
			"build": "0.1.0",
			"godot": "generator",
			"platform": "Generator",
			"started_utc": started,
			"detection":
			{"mode": "auto", "player": "Player (CharacterBody2D)", "deaths": "node_removal", "levels": "scene"},
		}
	)
	_event(PlaytraceSchema.LEVEL_ENTER, {"level": level})
	_pos_event()
	var death_center := _v(_planted["death_cluster"]["center"])
	if _rng.randf() < 0.6:
		for d in _rng.randi_range(1, 4):
			_walk_to(death_center + Vector2(-40, 0))
			var at := death_center + Vector2(_rng.randfn(0, 5), _rng.randfn(0, 3))
			_walk_to(at)
			_event(PlaytraceSchema.DEATH, {"p": _p(at), "data": {"cause": "auto"}})
			_t += 1000
			_pos = _v(_planted["spawn"])
			_pos_event()
	# jump over the spikes
	_walk_to(death_center + Vector2(-40, 0))
	_walk_to(death_center + Vector2(48, 0))
	var quit_center := _v(_planted["quit_point"]["center"])
	if _rng.randf() < 0.25:
		var at := quit_center + Vector2(_rng.randfn(0, 6), 0)
		_walk_to(at)
		_idle(_rng.randi_range(2000, 6000))
		_event(PlaytraceSchema.QUIT, {"p": _p(at)})
		return "\n".join(_lines) + "\n"
	_walk_to(quit_center)
	if _rng.randf() < 0.5:
		_backtrack()
	_walk_to(_v(_planted["exit"]))
	_event(PlaytraceSchema.LEVEL_COMPLETE, {"p": _p(_pos)})
	_event(PlaytraceSchema.LEVEL_EXIT, {"level": level})
	return "\n".join(_lines) + "\n"


func _backtrack() -> void:
	var from := _v(_planted["backtrack_loop"]["from"])
	var to := _v(_planted["backtrack_loop"]["to"])
	_walk_to(from)
	_walk_to(to)
	if _rng.randf() < 0.4:
		var stuck_at := _v(_planted["stuck_zone"]["center"]) + Vector2(_rng.randfn(0, 3), 0)
		_walk_to(stuck_at)
		var seconds := snappedf(_rng.randf_range(8.0, 15.0), 0.1)
		_idle(int(seconds * 1000))
		_event(PlaytraceSchema.STUCK, {"p": _p(stuck_at), "data": {"seconds": seconds}})
	_walk_to(from)
	_walk_to(Vector2(1250, GROUND_Y))


func _walk_to(target: Vector2) -> void:
	var step := WALK_SPEED_PX_S * SAMPLE_MS / 1000.0
	while _pos.distance_to(target) > step:
		_pos += (target - _pos).normalized() * step
		_t += SAMPLE_MS
		_pos_event()
	_pos = target
	_t += SAMPLE_MS
	_pos_event()


func _idle(ms: int) -> void:
	_t += ms


func _pos_event() -> void:
	var jitter := Vector2(0, _rng.randfn(0, 1.5))
	_event(PlaytraceSchema.POS, {"p": _p(_pos + jitter)})


func _event(type: String, fields: Dictionary) -> void:
	var e := {"t": _t, "type": type}
	e.merge(fields)
	_emit(e)


func _emit(d: Dictionary) -> void:
	_lines.append(JSON.stringify(d, "", false))


func _p(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), 0]


func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


func _uuid() -> String:
	var b := PackedByteArray()
	for i in 16:
		b.append(_rng.randi() & 0xff)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
