extends SceneTree
## Renders the docs screenshots of the overlay over the sandbox level with [PlaytraceOverlayExport]
## (the same drawing code as the editor). Needs a GPU (not --headless):
## [codeblock]
## godot --path . --script res://tests/golden/render_m3_overlay.gd
## [/codeblock]
## Writes docs/images/m3_overlay.png and m3_overlay_viridis.png (whole level, zoom 0.75, heatmap and deaths)
## and m3_overlay_zoom400.png (the quit point and hard step at 400 %), from 200 generated sessions, seed 1.

const LEVEL := "res://demo/sandbox.tscn"
const SESSIONS_DIR := "user://playtrace_render/m3"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gen := PlaytraceSessionGenerator.new()
	for f: String in PlaytraceSessionReader.list_sessions(SESSIONS_DIR):
		DirAccess.remove_absolute(f)
	gen.write(1, 200, LEVEL, SESSIONS_DIR)
	var records := PlaytraceSessionLibrary.load_dirs([SESSIONS_DIR] as Array[String], LEVEL)
	var overlay := PlaytraceHeatmapOverlay.new()
	overlay.level = LEVEL
	overlay.data = PlaytraceSessionLibrary.combine(records, LEVEL)
	overlay.show_stuck = false  # the M3 pictures show the M3 layers only
	overlay.show_quits = false
	var full := Rect2(-32, -64, 2112, 640)
	var shots := [
		["m3_overlay.png", PlaytraceHeatmapPalette.MAGMA, full, 0.75],
		["m3_overlay_viridis.png", PlaytraceHeatmapPalette.VIRIDIS, full, 0.75],
		["m3_overlay_zoom400.png", PlaytraceHeatmapPalette.MAGMA, Rect2(1080, 340, 240, 120), 4.0],
	]
	for shot: Array in shots:
		var result := PlaytraceHeatmapOverlay.compute(overlay.data, overlay.kernel_radius_px, shot[1])
		overlay.texture = ImageTexture.create_from_image(result.image)
		overlay.texture_rect = result.rect
		overlay.grid = result.grid
		var image := await PlaytraceOverlayExport.render(root, overlay, LEVEL, shot[2], shot[3])
		image.save_png(ProjectSettings.globalize_path("res://docs/images/" + shot[0]))
	print("Playtrace: rendered %d sessions, %d deaths" % [overlay.data.session_count, overlay.data.deaths.size()])
	overlay.shutdown()
	quit()
