extends SceneTree
## Renders the docs screenshots of the M3 overlay: the sandbox level with the heatmap and death layers,
## drawn by the same code as the editor ([method PlaytraceHeatmapOverlay.draw_layers]).
## Needs a GPU (not --headless):
## [codeblock]
## godot --path . --script res://tests/golden/render_m3_overlay.gd
## [/codeblock]
## Writes docs/images/m3_overlay.png and m3_overlay_viridis.png (whole level, zoom 0.75) and
## m3_overlay_zoom400.png (the quit point and hard step at 400 %), from 200 generated sessions, seed 1.

const LEVEL := "res://demo/sandbox.tscn"
const SESSIONS_DIR := "user://playtrace_render/m3"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gen := PlaytraceSessionGenerator.new()
	for f: String in PlaytraceSessionReader.list_sessions(SESSIONS_DIR):
		DirAccess.remove_absolute(f)
	gen.write(1, 200, LEVEL, SESSIONS_DIR)
	var data := PlaytraceLevelData.load_dirs([SESSIONS_DIR] as Array[String], LEVEL)
	var sigma := PlaytraceHeatmapOverlay.new().kernel_radius_px
	var shots := [
		["m3_overlay.png", PlaytraceHeatmapPalette.MAGMA, Vector2i(1584, 480), 0.75, Vector2(-32, -64)],
		["m3_overlay_viridis.png", PlaytraceHeatmapPalette.VIRIDIS, Vector2i(1584, 480), 0.75, Vector2(-32, -64)],
		["m3_overlay_zoom400.png", PlaytraceHeatmapPalette.MAGMA, Vector2i(960, 480), 4.0, Vector2(1080, 340)],
	]
	for shot: Array in shots:
		var result := PlaytraceHeatmapOverlay.compute(data, sigma, shot[1])
		var tex := ImageTexture.create_from_image(result["image"])
		await _shot("res://docs/images/" + shot[0], shot[2], shot[3], shot[4], tex, result["rect"], data.deaths)
	print("Playtrace: rendered %d sessions, %d deaths" % [data.session_count, data.deaths.size()])
	quit()


func _shot(
	path: String, size: Vector2i, zoom: float, offset: Vector2, tex: Texture2D, rect: Rect2, deaths: PackedVector2Array
) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var xform := PlaytraceOverlayTransform.canvas_transform(zoom, offset)
	var level: Node = load(LEVEL).instantiate()
	level.process_mode = Node.PROCESS_MODE_DISABLED  # keep the player where the scene puts it
	for cam: Node in level.find_children("*", "Camera2D", true, false):
		cam.free()  # the player's camera would replace our canvas transform and misalign the layers
	vp.add_child(level)
	var layer := CanvasLayer.new()  # not moved by canvas_transform, like the editor overlay control
	var overlay := Control.new()
	overlay.size = size
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	overlay.draw.connect(func() -> void: PlaytraceHeatmapOverlay.draw_layers(overlay, xform, tex, rect, deaths, 0.65))
	layer.add_child(overlay)
	vp.add_child(layer)
	root.add_child(vp)
	vp.canvas_transform = xform  # needs the viewport in the tree
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	vp.queue_free()
