extends Node
## The [code]Playtrace[/code] autoload: records playtest sessions from a running game.
##
## In plug-and-play mode it finds the player, levels, deaths, stuck moments and quits on its own.
## The methods below are the manual API (contract 6.1). The first explicit call for a feature
## turns off auto-detection of that feature for the rest of the run (takeover rule), so mixing
## auto and manual never counts anything twice. All methods are safe no-ops when recording is off.
## No [code]class_name[/code]: it would clash with the autoload name (D-006).
##
## Recording is on for editor runs and debug exports, and off in release exports unless
## [code]playtrace/recording/enabled_in_release[/code] is set. It is also off when the main loop
## is a custom script (command-line tools, test runners; D-030).

## Emitted when a new session file has been started.
signal session_started(session_id: String)
## Emitted when a session has been finished and its file fully written to [param path].
signal session_finished(session_id: String, path: String)

const _RESOLVE_INTERVAL_MS := 500
const _RELOAD_WINDOW_MS := 1000
const _FLUSH_INTERVAL_MS := 5000
const _WEB_HIDDEN_QUIT_MS := 30000

var _enabled := false
var _sessions_dir := PlaytraceSchema.SESSIONS_DIR
var _game_id := ""
var _writer: PlaytraceSessionWriter
var _session_id := ""
var _start_ms := 0
var _finished := false

# Hooks so tests can drive time, the scene and pausing; defaults read the real engine state.
var _now_fn: Callable
var _scene_fn: Callable
var _paused_fn: Callable

var _mode := "auto"
var _auto_player := true
var _auto_levels := true
var _auto_deaths := true
var _pos_interval_ms := 200
var _pos_min_distance := 2.0
var _stuck := PlaytraceStuckDetector.new()

var _player: Node2D
var _next_resolve_ms := 0
var _last_pos := Vector2.ZERO
var _first_pos := Vector2.INF
var _moved := false
var _last_written_pos := Vector2.INF
var _next_pos_ms := 0
var _scene: Node
var _level := ""
var _pending_exit := {}
var _last_step_ms := 0
var _next_flush_ms := 0

var _js_visibility_cb: JavaScriptObject
var _js_timeout_cb: JavaScriptObject
var _hidden_since_ms := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.get_main_loop().get_script() != null:
		set_process(false)  # CLI tool or test runner, not a game (D-030)
		return
	var on_in_release: bool = PlaytraceSettings.get_value(PlaytraceSettings.RECORDING_ENABLED_IN_RELEASE)
	_configure(OS.is_debug_build() or on_in_release, PlaytraceSchema.SESSIONS_DIR)


func _process(_delta: float) -> void:
	_step()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE]:
		_finish_session()


## Tracks [param node] as the player; disables auto player detection.
func track(node: Node2D) -> void:
	if not _ensure_started():
		return
	_auto_player = false
	_set_player(node)


## Records a death at the player's position; disables auto deaths. Empty cause is written as "manual".
func death(cause: String = "") -> void:
	if not _ensure_started():
		return
	_auto_deaths = false
	_pending_exit = {}
	_end_stuck()
	_write(PlaytraceSchema.DEATH, {"p": _p(_current_pos()), "data": {"cause": cause if cause != "" else "manual"}})
	_stuck.reset()


## Sets the current level id; disables auto level detection.
func level(id: String) -> void:
	if not _ensure_started():
		return
	_auto_levels = false
	_enter_level(id)


## Records a custom event with a name and optional data.
func event(event_name: StringName, data: Dictionary = {}) -> void:
	if not _ensure_started():
		return
	_write(PlaytraceSchema.CUSTOM, {"name": String(event_name), "data": data})


## Records reaching a checkpoint at the player's position.
func checkpoint(checkpoint_name: String) -> void:
	if not _ensure_started():
		return
	_write(PlaytraceSchema.CHECKPOINT, {"p": _p(_current_pos()), "data": {"name": checkpoint_name}})


## Records that the current level was completed.
func complete() -> void:
	if not _ensure_started():
		return
	_write(PlaytraceSchema.LEVEL_COMPLETE, {"p": _p(_current_pos())})
	_writer.flush()


## Returns true while a session is being recorded.
func is_recording() -> bool:
	return _enabled and not _finished


## Returns the detection report: same shape as the header's detection plus "warnings": Array[String].
func get_detection_report() -> Dictionary:
	var warnings: Array[String] = []
	var player_ok := is_instance_valid(_player)
	if _auto_player and not player_ok:
		warnings.append(PlaytraceSchema.WARN_PLAYER_NOT_FOUND)
	if player_ok and _first_pos != Vector2.INF and not _moved:
		warnings.append(PlaytraceSchema.WARN_PLAYER_NEVER_MOVED)
	return {
		"mode": _mode,
		"player": "%s (%s)" % [_player.name, _player.get_class()] if player_ok else "",
		"deaths": "node_removal" if _auto_deaths else "manual",
		"levels": "scene" if _auto_levels else "manual",
		"warnings": warnings,
	}


# --- internal -------------------------------------------------------------------------------


## Internal: sets up a run. Tests call this directly with fake hooks and settings overrides.
func _configure(enabled: bool, sessions_dir: String, hooks: Dictionary = {}, settings: Dictionary = {}) -> void:
	_enabled = enabled
	_sessions_dir = sessions_dir
	_now_fn = hooks.get("now", Time.get_ticks_msec)
	_scene_fn = hooks.get("scene", func() -> Node: return get_tree().current_scene)
	_paused_fn = hooks.get("paused", func() -> bool: return get_tree().paused)
	var s := PlaytraceSettings.defaults()
	for key: String in s:
		s[key] = settings.get(key, PlaytraceSettings.get_value(key))
	_mode = s[PlaytraceSettings.SETUP_MODE]
	var manual := _mode == "manual"
	_auto_player = not manual and s[PlaytraceSettings.AUTO_PLAYER]
	_auto_levels = not manual and s[PlaytraceSettings.AUTO_LEVELS]
	_auto_deaths = not manual and s[PlaytraceSettings.AUTO_DEATHS]
	_pos_interval_ms = int(float(s[PlaytraceSettings.POS_INTERVAL_S]) * 1000.0)
	_pos_min_distance = s[PlaytraceSettings.POS_MIN_DISTANCE_PX]
	_stuck.radius_px = s[PlaytraceSettings.STUCK_RADIUS_PX]
	_stuck.threshold_ms = int(float(s[PlaytraceSettings.STUCK_SECONDS]) * 1000.0)
	_game_id = str(s[PlaytraceSettings.GAME_ID])


## Internal: one recorder frame. Called from _process, or by tests with a fake clock.
func _step() -> void:
	if not _ensure_started():
		return
	var now: int = _now_fn.call()
	var dt := now - _last_step_ms
	_last_step_ms = now
	_check_pending_exit(now)
	if _auto_levels:
		_check_level()
	if _auto_player and not is_instance_valid(_player) and now >= _next_resolve_ms:
		_next_resolve_ms = now + _RESOLVE_INTERVAL_MS
		_resolve_player()
	if is_instance_valid(_player) and _player.is_inside_tree():
		_sample(_player.global_position, now, dt)
	if now >= _next_flush_ms:
		_next_flush_ms = now + _FLUSH_INTERVAL_MS
		_writer.flush()


func _sample(pos: Vector2, now: int, dt: int) -> void:
	_last_pos = pos
	if _first_pos == Vector2.INF:
		_first_pos = pos
	elif not _moved and pos.distance_to(_first_pos) > _pos_min_distance:
		_moved = true
	# Fixed-rate schedule (no drift at 60 fps); after a long gap it restarts from now.
	if now >= _next_pos_ms:
		_next_pos_ms = maxi(_next_pos_ms + _pos_interval_ms, now - _pos_interval_ms + 1)
		if _last_written_pos == Vector2.INF or pos.distance_to(_last_written_pos) > _pos_min_distance:
			_last_written_pos = pos
			_write(PlaytraceSchema.POS, {"p": _p(pos)})
	var ended := _stuck.step(pos, dt, _paused_fn.call())
	if not ended.is_empty():
		_write(PlaytraceSchema.STUCK, {"p": _p(ended["p"]), "data": {"seconds": ended["seconds"]}})


func _ensure_started() -> bool:
	if not _enabled or _finished:
		return false
	if _writer != null:
		return true
	_session_id = _uuid_v4()
	_writer = PlaytraceSessionWriter.new()
	if not _writer.open(_sessions_dir.path_join(_session_id + ".jsonl")):
		push_warning("Playtrace: cannot create a session file in %s; recording is off." % _sessions_dir)
		_enabled = false
		return false
	_start_ms = _now_fn.call()
	_last_step_ms = _start_ms
	_next_flush_ms = _start_ms + _FLUSH_INTERVAL_MS
	if _auto_player:
		_resolve_player()
	var detection := get_detection_report()
	(
		_writer
		. write(
			{
				"schema": PlaytraceSchema.VERSION,
				"type": PlaytraceSchema.SESSION_START,
				"session": _session_id,
				"game": _game_id,
				"build": str(ProjectSettings.get_setting("application/config/version", "")),
				"godot": Engine.get_version_info()["string"],
				"platform": OS.get_name(),
				"started_utc": Time.get_datetime_string_from_system(true) + "Z",
				"detection": detection,
			}
		)
	)
	_writer.flush()
	_log_detection(detection)
	if OS.has_feature("web"):
		_watch_web_visibility()
	session_started.emit(_session_id)
	return true


func _log_detection(d: Dictionary) -> void:
	var who: String = d["player"] if d["player"] != "" else "no player yet"
	print("Playtrace: tracking %s · deaths: %s · levels: %s" % [who, d["deaths"], d["levels"]])
	if PlaytraceSchema.WARN_PLAYER_NOT_FOUND in d["warnings"]:
		push_warning('Playtrace: player not found. Add your player to group "player" or call Playtrace.track(player).')


func _check_level() -> void:
	var scene: Node = _scene_fn.call()
	if scene == null or scene == _scene:
		return
	_scene = scene
	_enter_level(_level_id(scene))
	if _auto_player:
		_set_player(null)
		_next_resolve_ms = 0


func _enter_level(id: String) -> void:
	_end_stuck()
	_stuck.reset()
	if _level != "":
		_write(PlaytraceSchema.LEVEL_EXIT, {"level": _level})
	_level = id
	_write(PlaytraceSchema.LEVEL_ENTER, {"level": id})
	_writer.flush()
	_last_written_pos = Vector2.INF
	_next_pos_ms = 0


# Auto player: first Node2D in group "player" inside the current scene, else the first
# CharacterBody2D in the scene. Searching is throttled to every 0.5 s while nothing is found.
func _resolve_player() -> void:
	var scene: Node = _scene_fn.call()
	if scene == null:
		return
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n is Node2D and (n == scene or scene.is_ancestor_of(n)):
			_set_player(n)
			return
	var bodies := scene.find_children("*", "CharacterBody2D", true, false)
	if not bodies.is_empty():
		_set_player(bodies[0])


func _set_player(node: Node2D) -> void:
	if is_instance_valid(_player) and _player.tree_exiting.is_connected(_on_player_exiting):
		_player.tree_exiting.disconnect(_on_player_exiting)
	_player = node
	_stuck.reset()
	if node != null:
		node.tree_exiting.connect(_on_player_exiting)


# Auto death, part 1: the tracked node is leaving the tree. Whether that is a death is decided
# on the next frame in _check_pending_exit, once we can see what happened to the scene.
func _on_player_exiting() -> void:
	if _auto_deaths and is_instance_valid(_player):
		_pending_exit = {
			"p": _player.global_position,
			"ms": _now_fn.call(),
			"scene": _scene_fn.call(),
			"path": _level,
		}
	_set_player(null)
	_next_resolve_ms = 0


# Auto death, part 2. It is a death when either
# - the scene that held the player is still the running scene (the player node was removed), or
# - a new instance of the same level became the current scene within 1 s (the level reloaded).
# A switch to a different level is not a death. Each tracked node can cause at most one death.
func _check_pending_exit(now: int) -> void:
	if _pending_exit.is_empty():
		return
	var old: Variant = _pending_exit["scene"]
	var current: Node = _scene_fn.call()
	var died := false
	if is_instance_valid(old) and current == old and (old as Node).is_inside_tree():
		died = true
	elif current != null and current != old:
		var same_level: bool = _level_id(current) == _pending_exit["path"]
		died = same_level and now - int(_pending_exit["ms"]) <= _RELOAD_WINDOW_MS
	elif now - int(_pending_exit["ms"]) <= _RELOAD_WINDOW_MS:
		return  # scene not swapped in yet; wait
	if died:
		_end_stuck()
		_stuck.reset()
		_write(PlaytraceSchema.DEATH, {"p": _p(_pending_exit["p"]), "data": {"cause": "auto"}})
	_pending_exit = {}


func _level_id(scene: Node) -> String:
	return scene.scene_file_path if scene.scene_file_path != "" else str(scene.name)


func _end_stuck() -> void:
	var ended := _stuck.finish()
	if not ended.is_empty():
		_write(PlaytraceSchema.STUCK, {"p": _p(ended["p"]), "data": {"seconds": ended["seconds"]}})


func _finish_session() -> void:
	if _writer == null or _finished:
		return
	_end_stuck()
	_write(PlaytraceSchema.QUIT, {"p": _p(_current_pos())})
	_writer.close()
	_finished = true
	session_finished.emit(_session_id, _writer.path)


func _write(type: String, fields: Dictionary) -> void:
	var e := {"t": int(_now_fn.call()) - _start_ms, "type": type}
	e.merge(fields)
	_writer.write(e)


func _current_pos() -> Vector2:
	if is_instance_valid(_player) and _player.is_inside_tree():
		_last_pos = _player.global_position
	return _last_pos


func _p(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), 0]


func _uuid_v4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


# Web: flush as soon as the tab is hidden (the browser may kill it), and end the session as a
# quit if it stays hidden for 30 s. Uses setTimeout because _process stops in hidden tabs.
func _watch_web_visibility() -> void:
	var document := JavaScriptBridge.get_interface("document")
	if document == null:
		return
	_js_visibility_cb = JavaScriptBridge.create_callback(_on_web_visibility)
	_js_timeout_cb = JavaScriptBridge.create_callback(_on_web_hidden_timeout)
	document.addEventListener("visibilitychange", _js_visibility_cb)


func _on_web_visibility(_args: Array) -> void:
	if JavaScriptBridge.get_interface("document").visibilityState == "hidden":
		_hidden_since_ms = Time.get_ticks_msec()
		_writer.flush()
		JavaScriptBridge.get_interface("window").setTimeout(_js_timeout_cb, _WEB_HIDDEN_QUIT_MS)
	else:
		_hidden_since_ms = -1


func _on_web_hidden_timeout(_args: Array) -> void:
	if _hidden_since_ms >= 0 and Time.get_ticks_msec() - _hidden_since_ms >= _WEB_HIDDEN_QUIT_MS - 50:
		_finish_session()
