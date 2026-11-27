@tool
class_name PlaytraceHeatmapOverlay
extends RefCounted
## The layers drawn over the 2D editor viewport (heatmap, deaths, stuck zones, quit points), their
## settings, and the background work behind them. Owned by the editor plugin; the dock edits it.
##
## Work: reading session files ([PlaytraceSessionLibrary]), filtering, the [PlaytraceDensityGrid], its
## colours and the [PlaytraceInsights] run as one [WorkerThreadPool] task, so the editor never waits.
## At most one task runs at a time; changes made meanwhile are merged into one follow-up run. Only a
## reload re-reads files; filters, radius and palette reuse the loaded records.
##
## Drawing: [method draw] maps world to overlay pixels with the editor's canvas transform, so every layer
## stays exact under pan and zoom. The layers go into two canvas items of our own under the target
## control (heatmap, then markers), so their texture filter never touches the editor's own drawing.
## Markers are clustered per zoom level ([PlaytraceMarkerClusters]) into numbered badges.

## Emitted when something visible changed and the viewport should redraw.
signal changed
## Emitted when new records, insights or setup health are available (the dock refreshes).
signal data_changed

## Half the length of a death X mark, in overlay pixels (constant at every zoom).
const DEATH_MARK_PX := 5.0
## Colour of the death marks.
const DEATH_COLOR := Color(1.0, 0.27, 0.3)
## Muted red of the quit door icons.
const QUIT_COLOR := Color(0.78, 0.36, 0.36)
## Colour of the stuck rings.
const STUCK_COLOR := Color(1.0, 0.82, 0.35)
## Markers closer than this on screen merge into one badge.
const BADGE_PX := 18.0
## Stuck ring radius in screen px per stuck second (clamped to [constant STUCK_MIN_PX]..[constant STUCK_MAX_PX]).
const STUCK_PX_PER_S := 1.5
## Smallest stuck ring radius.
const STUCK_MIN_PX := 10.0
## Largest stuck ring radius.
const STUCK_MAX_PX := 60.0
## Directories scanned for session files.
const DEFAULT_DIRS: Array[String] = [PlaytraceSchema.SESSIONS_DIR]

## Draw anything at all.
var enabled := true:
	set(v):
		enabled = v
		changed.emit()
## Show the movement heatmap.
var show_heatmap := true:
	set(v):
		show_heatmap = v
		changed.emit()
## Show death marks.
var show_deaths := true:
	set(v):
		show_deaths = v
		changed.emit()
## Show stuck rings.
var show_stuck := true:
	set(v):
		show_stuck = v
		changed.emit()
## Show quit door icons.
var show_quits := true:
	set(v):
		show_quits = v
		changed.emit()
## Heatmap opacity, 0..1 (default 65 %, spec 7.3).
var opacity := 0.65:
	set(v):
		opacity = clampf(v, 0.0, 1.0)
		changed.emit()
## Palette id from [PlaytraceHeatmapPalette].
var palette := PlaytraceHeatmapPalette.MAGMA:
	set(v):
		palette = v
		_request(false)
## Gaussian kernel sigma in world pixels.
var kernel_radius_px := 16.0:
	set(v):
		kernel_radius_px = maxf(v, 1.0)
		_request(false)
## Session filter (keys of [constant PlaytraceSessionLibrary.NO_FILTER]).
var filter := PlaytraceSessionLibrary.NO_FILTER.duplicate():
	set(v):
		filter = v
		_request(false)
## Directories scanned for session files.
var session_dirs: Array[String] = DEFAULT_DIRS.duplicate()
## Floors of the edited level (from [PlaytraceLevelSurfaces]), for never-visited insights.
var surfaces: Array[Rect2] = []
## Font of the badge numbers.
var font: Font = ThemeDB.fallback_font

## Level shown (the edited scene's path); empty shows nothing.
var level := ""
## Heatmap texture, or null while there is no data.
var texture: ImageTexture
## World rect the texture covers.
var texture_rect := Rect2()
## Every loaded session record (all levels), oldest first.
var records: Array[Dictionary] = []
## The records that pass [member filter].
var shown: Array[Dictionary] = []
## The combined data of [member shown] in [member level].
var data := PlaytraceLevelData.new()
## The movement density grid behind the heatmap.
var grid := PlaytraceDensityGrid.new()
## The Insights list ([method PlaytraceInsights.compute]).
var insights: Array[Dictionary] = []
## True while a background task runs.
var busy := false

var _task_id := -1
var _dirty := false
var _reload := false
var _canvases := {}  # target canvas instance id -> [heat RID, marks RID]
var _hits: Array[Dictionary] = []  # markers drawn last time, for clicks: {screen, kind, cluster}
var _cluster_cache := {}  # "kind/zoom" -> clusters


## Shows level [param level_id] and loads its sessions in the background.
func set_level(level_id: String) -> void:
	if level_id == level:
		return
	level = level_id
	texture = null
	data = PlaytraceLevelData.new(level_id)
	insights = []
	_cluster_cache.clear()
	changed.emit()
	data_changed.emit()
	reload()


## Re-reads the session files (for example after a new playtest).
func reload() -> void:
	_request(true)


## Blocks until the running task ends and frees the canvas items. Call before the plugin is removed.
func shutdown() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_dirty = false
	for rids: Array in _canvases.values():
		for rid: RID in rids:
			RenderingServer.free_rid(rid)
	_canvases.clear()


## Frees the canvas items made for [param canvas] (for example after an offscreen export).
func release(canvas: CanvasItem) -> void:
	var rids: Array = _canvases.get(canvas.get_instance_id(), [])
	for rid: RID in rids:
		RenderingServer.free_rid(rid)
	_canvases.erase(canvas.get_instance_id())


## True when the stuck rings are visible and should pulse (the plugin then redraws every frame).
func animating() -> bool:
	return enabled and show_stuck and not level.is_empty() and not data.stuck_points.is_empty()


## Draws the enabled layers under [param canvas] using the editor's canvas transform [param xform].
## [param time_s] drives the stuck rings' pulse.
func draw(canvas: CanvasItem, xform: Transform2D, time_s: float = 0.0) -> void:
	var rids := _rids_for(canvas)
	var heat: RID = rids[0]
	var marks: RID = rids[1]
	RenderingServer.canvas_item_clear(heat)
	RenderingServer.canvas_item_clear(marks)
	_hits.clear()
	if not enabled or level.is_empty():
		return
	if show_heatmap and texture != null and opacity > 0.0:
		RenderingServer.canvas_item_set_transform(heat, xform)
		RenderingServer.canvas_item_add_texture_rect(
			heat, texture_rect, texture.get_rid(), false, Color(1, 1, 1, opacity)
		)
	var zoom := xform.get_scale().x
	if show_stuck:
		_draw_stuck(marks, xform, zoom, time_s)
	if show_quits:
		_draw_quits(marks, xform, zoom)
	if show_deaths:
		_draw_deaths(marks, xform, zoom)


## The marker under overlay position [param screen] from the last [method draw], or {}.
## Returns [code]{kind, cluster, screen}[/code]; kind is "death", "stuck" or "quit".
func hit(screen: Vector2) -> Dictionary:
	var best := {}
	var best_d := BADGE_PX * 0.75
	for h: Dictionary in _hits:
		var d: float = (h.screen as Vector2).distance_to(screen)
		if d < best_d:
			best_d = d
			best = h
	return best


## The popover text of marker [param h] (from [method hit]): {title, lines: Array[String], sessions}.
func describe(h: Dictionary) -> Dictionary:
	var c: Dictionary = h.cluster
	var players := maxi(data.session_count, 1)
	var session_of: PackedInt32Array = data.death_session
	if h.kind == "stuck":
		session_of = data.stuck_session
	elif h.kind == "quit":
		session_of = data.quit_session
	var sessions := {}
	for i: int in c.members:
		sessions[session_of[i]] = true
	var share := roundi(100.0 * sessions.size() / players)
	var avg := PlaytraceInsights.time_near(grid, c.pos, PlaytraceInsights.HOTSPOT_PX, players)
	var lines: Array[String] = []
	var title := ""
	match h.kind:
		"death":
			title = "Death hotspot" if c.count > 1 else "Death"
			lines.append("%d deaths" % c.count)
			lines.append("%d %% of players died here" % share)
		"stuck":
			title = "Stuck zone"
			lines.append("Stuck %d times, %d s in total" % [c.count, roundi(c.weight)])
			lines.append("%d %% of players got stuck here" % share)
		"quit":
			title = "Quit point"
			lines.append("%d players quit here" % c.count)
			lines.append("%d %% of players" % share)
	lines.append("Average time spent here: %.1f s per player" % avg)
	var ids := PackedInt32Array(sessions.keys())
	ids.sort()
	return {"title": title, "lines": lines, "sessions": ids}


## Line segments (pairs of overlay points) of an X mark of half-size [param half_px] at each death.
static func death_segments(xform: Transform2D, points: PackedVector2Array, half_px: float) -> PackedVector2Array:
	var segs := PackedVector2Array()
	segs.resize(points.size() * 4)
	var a := Vector2(half_px, half_px)
	var b := Vector2(half_px, -half_px)
	for i in points.size():
		var s := PlaytraceOverlayTransform.world_to_overlay(xform, points[i])
		segs[i * 4] = s - a
		segs[i * 4 + 1] = s + a
		segs[i * 4 + 2] = s - b
		segs[i * 4 + 3] = s + b
	return segs


## Builds the heatmap of [param level_data]. Pure and thread-safe; returns
## [code]{image: Image, rect: Rect2, grid: PlaytraceDensityGrid}[/code] (image is null without positions).
static func compute(level_data: PlaytraceLevelData, sigma_px: float, palette_id: int) -> Dictionary:
	var g := PlaytraceDensityGrid.build_level(level_data, sigma_px)
	var image := PlaytraceHeatmapPalette.colorize(g, palette_id)
	if image != null:
		image.generate_mipmaps()  # zoomed out, the texture is drawn smaller than its cells; avoids shimmer
	return {"image": image, "rect": g.world_rect(), "grid": g}


func _rids_for(canvas: CanvasItem) -> Array:
	var id := canvas.get_instance_id()
	if not _canvases.has(id):
		var heat := RenderingServer.canvas_item_create()
		var marks := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_default_texture_filter(
			heat, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		)
		_canvases[id] = [heat, marks]
	var rids: Array = _canvases[id]
	# Re-parent every time: cheap, and survives the editor recreating its viewport control.
	RenderingServer.canvas_item_set_parent(rids[0], canvas.get_canvas_item())
	RenderingServer.canvas_item_set_parent(rids[1], canvas.get_canvas_item())
	RenderingServer.canvas_item_set_draw_index(rids[0], 0)
	RenderingServer.canvas_item_set_draw_index(rids[1], 1)
	return rids


func _clusters(kind: String, points: PackedVector2Array, zoom: float, weights := PackedFloat64Array()) -> Array:
	var key := "%s/%.4f" % [kind, zoom]
	if not _cluster_cache.has(key):
		if _cluster_cache.size() > 32:
			_cluster_cache.clear()
		_cluster_cache[key] = PlaytraceMarkerClusters.cluster(points, BADGE_PX / maxf(zoom, 0.0001), weights)
	return _cluster_cache[key]


func _draw_deaths(ci: RID, xform: Transform2D, zoom: float) -> void:
	var singles := PackedVector2Array()
	var badges: Array[Dictionary] = []
	for c: Dictionary in _clusters("death", data.deaths, zoom):
		_hits.append({"screen": xform * (c.pos as Vector2), "kind": "death", "cluster": c})
		if c.count == 1:
			singles.append(c.pos)
		else:
			badges.append(c)
	if not singles.is_empty():
		var segs := death_segments(xform, singles, DEATH_MARK_PX)
		# Soft dark outline: two wide translucent passes under the coloured stroke.
		RenderingServer.canvas_item_add_multiline(ci, segs, [Color(0, 0, 0, 0.25)], 6.0, true)
		RenderingServer.canvas_item_add_multiline(ci, segs, [Color(0, 0, 0, 0.5)], 4.0, true)
		RenderingServer.canvas_item_add_multiline(ci, segs, [DEATH_COLOR], 2.0, true)
	for c: Dictionary in badges:
		_badge(ci, xform * (c.pos as Vector2), c.count, DEATH_COLOR)


func _draw_quits(ci: RID, xform: Transform2D, zoom: float) -> void:
	for c: Dictionary in _clusters("quit", data.quit_points, zoom):
		var s: Vector2 = xform * (c.pos as Vector2)
		_hits.append({"screen": s, "kind": "quit", "cluster": c})
		# A door: a rounded-looking panel with a dark outline and a knob.
		var door := Rect2(s - Vector2(5, 14), Vector2(10, 14))
		RenderingServer.canvas_item_add_rect(ci, door.grow(1.5), Color(0, 0, 0, 0.55))
		RenderingServer.canvas_item_add_rect(ci, door, QUIT_COLOR)
		RenderingServer.canvas_item_add_rect(ci, Rect2(s + Vector2(1.5, -7.5), Vector2(2, 2)), Color(0.25, 0.08, 0.08))
		if c.count > 1:
			_badge(ci, s + Vector2(8, -16), c.count, QUIT_COLOR, 7.0)


func _draw_stuck(ci: RID, xform: Transform2D, zoom: float, time_s: float) -> void:
	var pulse := 0.5 + 0.5 * sin(time_s * TAU / 1.6)
	for c: Dictionary in _clusters("stuck", data.stuck_points, zoom, data.stuck_seconds):
		var s: Vector2 = xform * (c.pos as Vector2)
		_hits.append({"screen": s, "kind": "stuck", "cluster": c})
		var r := clampf(c.weight * STUCK_PX_PER_S, STUCK_MIN_PX, STUCK_MAX_PX) * (1.0 + 0.08 * pulse)
		RenderingServer.canvas_item_add_circle(ci, s, r, Color(STUCK_COLOR, 0.10 + 0.08 * pulse), true)
		_ring(ci, s, r, Color(0, 0, 0, 0.45), 4.0)
		_ring(ci, s, r, Color(STUCK_COLOR, 0.65 + 0.3 * pulse), 2.0)
		if c.count > 1:
			_badge(ci, s + Vector2(r * 0.7, -r * 0.7), c.count, Color(0.85, 0.65, 0.2), 7.0)


func _ring(ci: RID, centre: Vector2, r: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := clampi(int(r), 24, 64)
	for i in n + 1:
		pts.append(centre + Vector2.from_angle(TAU * i / n) * r)
	RenderingServer.canvas_item_add_polyline(ci, pts, [color], width, true)


func _badge(ci: RID, centre: Vector2, count: int, color: Color, radius: float = 9.0) -> void:
	var text := str(count) if count < 1000 else "%dk" % (count / 1000)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var r := maxf(radius, size.x * 0.5 + 4.0)
	RenderingServer.canvas_item_add_circle(ci, centre, r + 1.5, Color(0, 0, 0, 0.55), true)
	RenderingServer.canvas_item_add_circle(ci, centre, r, color, true)
	var base := centre + Vector2(-size.x * 0.5, font.get_ascent(11) - size.y * 0.5)
	font.draw_string(ci, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


func _request(reload_data: bool) -> void:
	_reload = _reload or reload_data
	_dirty = true
	if _task_id == -1 and not level.is_empty():
		_start()


func _start() -> void:
	var reuse: Array[Dictionary] = []
	if not _reload:
		reuse = records
	var reread := _reload or records.is_empty()
	_dirty = false
	_reload = false
	busy = true
	var job := _job.bind(
		reread,
		reuse,
		level,
		session_dirs.duplicate(),
		filter.duplicate(),
		kernel_radius_px,
		palette,
		surfaces.duplicate()
	)
	_task_id = WorkerThreadPool.add_task(job, false, "Playtrace heatmap")


# Runs on a WorkerThreadPool thread. Touches no state of this object; hands the result to _finish.
func _job(
	reread: bool,
	reuse: Array[Dictionary],
	level_id: String,
	dirs: Array[String],
	by: Dictionary,
	sigma_px: float,
	palette_id: int,
	floors: Array[Rect2]
) -> void:
	var all := PlaytraceSessionLibrary.load_dirs(dirs, level_id) if reread else reuse
	var picked := PlaytraceSessionLibrary.filter(all, by)
	var combined := PlaytraceSessionLibrary.combine(picked, level_id)
	var result := compute(combined, sigma_px, palette_id)
	(
		result
		. merge(
			{
				"level": level_id,
				"records": all,
				"shown": picked,
				"data": combined,
				"insights": PlaytraceInsights.compute(combined, result.grid, floors),
			}
		)
	)
	_finish.call_deferred(result)


func _finish(result: Dictionary) -> void:
	if _task_id == -1:
		return  # shut down meanwhile
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	busy = false
	if result.level == level:
		records = result.records
		shown = result.shown
		data = result.data
		grid = result.grid
		insights = result.insights
		texture_rect = result.rect
		var image: Image = result.image
		texture = null if image == null else ImageTexture.create_from_image(image)
		_cluster_cache.clear()
		changed.emit()
		data_changed.emit()
	if _dirty and not level.is_empty():
		_start()
