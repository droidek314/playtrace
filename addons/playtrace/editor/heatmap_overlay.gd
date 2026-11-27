@tool
class_name PlaytraceHeatmapOverlay
extends RefCounted
## The density and death layers drawn over the 2D editor viewport, and the background work behind them.
##
## Owned by the editor plugin. Loading session files, building the [PlaytraceDensityGrid] and colouring
## it run as one [WorkerThreadPool] task, so the editor never waits on them. At most one task runs at
## a time: requests made while it runs are merged into one follow-up run. The finished [Image] is turned
## into an [ImageTexture] on the main thread, then [signal changed] asks the plugin to redraw.
## Drawing is [method draw_layers], which only maps world to overlay pixels with the editor's canvas
## transform, so the layers stay exact under pan and zoom.

## Emitted when something visible changed and the viewport should redraw.
signal changed

## Half the length of a death X mark, in overlay pixels (constant at every zoom).
const DEATH_MARK_PX := 5.0
## Colour of the death X marks.
const DEATH_COLOR := Color(1.0, 0.27, 0.3)

## Draw anything at all.
var enabled := true:
	set(v):
		enabled = v
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
var kernel_radius_px := 32.0:
	set(v):
		kernel_radius_px = maxf(v, 1.0)
		_request(false)
## Directories scanned for session files.
var session_dirs: Array[String] = [PlaytraceSchema.SESSIONS_DIR]

## Level shown (the edited scene's path); empty shows nothing.
var level := ""
## Heatmap texture, or null while there is no data.
var texture: ImageTexture
## World rect the texture covers.
var texture_rect := Rect2()
## Death positions for [member level].
var deaths := PackedVector2Array()
## Sessions that entered [member level].
var session_count := 0

var _data: PlaytraceLevelData
var _task_id := -1
var _dirty := false
var _reload := false


## Shows level [param level_id] and loads its sessions in the background.
func set_level(level_id: String) -> void:
	if level_id == level:
		return
	level = level_id
	texture = null
	deaths = PackedVector2Array()
	session_count = 0
	changed.emit()
	reload()


## Re-reads the session files (for example after a new playtest).
func reload() -> void:
	_request(true)


## Blocks until the running task ends. Call before the plugin is removed.
func shutdown() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_dirty = false


## Draws the enabled layers on [param canvas] using the editor's canvas transform [param xform].
func draw(canvas: CanvasItem, xform: Transform2D) -> void:
	if enabled and not level.is_empty():
		draw_layers(canvas, xform, texture, texture_rect, deaths, opacity)


## Draws a heatmap texture and death marks. Used by the plugin and by the docs/golden renderer.
static func draw_layers(
	canvas: CanvasItem,
	xform: Transform2D,
	heat: Texture2D,
	heat_rect: Rect2,
	death_points: PackedVector2Array,
	heat_opacity: float
) -> void:
	if heat != null and heat_opacity > 0.0:
		canvas.draw_set_transform_matrix(xform)
		canvas.draw_texture_rect(heat, heat_rect, false, Color(1, 1, 1, heat_opacity))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	if death_points.is_empty():
		return
	var segs := death_segments(xform, death_points, DEATH_MARK_PX)
	# Soft dark outline: two wide translucent passes under the coloured stroke.
	canvas.draw_multiline(segs, Color(0, 0, 0, 0.25), 6.0, true)
	canvas.draw_multiline(segs, Color(0, 0, 0, 0.5), 4.0, true)
	canvas.draw_multiline(segs, DEATH_COLOR, 2.0, true)


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


## Builds everything the overlay shows from [param data]. Pure and thread-safe; returns
## [code]{image: Image, rect: Rect2}[/code] (image is null when there are no positions).
static func compute(data: PlaytraceLevelData, sigma_px: float, palette_id: int) -> Dictionary:
	var grid := PlaytraceDensityGrid.build(data.paths, sigma_px, data.bounds)
	return {"image": PlaytraceHeatmapPalette.colorize(grid, palette_id), "rect": grid.world_rect()}


func _request(reload_data: bool) -> void:
	_reload = _reload or reload_data
	_dirty = true
	if _task_id == -1 and not level.is_empty():
		_start()


func _start() -> void:
	var data: PlaytraceLevelData = null if _reload or _data == null or _data.level != level else _data
	_dirty = false
	_reload = false
	var job := _job.bind(data, level, session_dirs.duplicate(), kernel_radius_px, palette)
	_task_id = WorkerThreadPool.add_task(job, false, "Playtrace heatmap")


# Runs on a WorkerThreadPool thread. Touches no state of this object; hands the result to _finish.
func _job(data: PlaytraceLevelData, level_id: String, dirs: Array[String], sigma_px: float, palette_id: int) -> void:
	if data == null:
		data = PlaytraceLevelData.load_dirs(dirs, level_id)
	var result := compute(data, sigma_px, palette_id)
	result["data"] = data
	_finish.call_deferred(result)


func _finish(result: Dictionary) -> void:
	if _task_id == -1:
		return  # shut down meanwhile
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var data: PlaytraceLevelData = result["data"]
	if data.level == level:
		_data = data
		deaths = data.deaths
		session_count = data.session_count
		texture_rect = result["rect"]
		var image: Image = result["image"]
		texture = null if image == null else ImageTexture.create_from_image(image)
		changed.emit()
	if _dirty and not level.is_empty():
		_start()
