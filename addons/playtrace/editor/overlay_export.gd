@tool
class_name PlaytraceOverlayExport
extends RefCounted
## Renders a level with the Playtrace layers on top into an [Image], offscreen: the scene is instanced
## into a [SubViewport] and [PlaytraceHeatmapOverlay] draws over it with the same code as in the editor.
## Used by the dock's "Save PNG" and by the docs screenshot script. Needs a renderer (not --headless).

## Longest side of an exported image, in pixels.
const MAX_SIDE := 4096


## Renders [param scene_path] with [param overlay]'s layers over world rect [param rect] at [param zoom],
## inside [param parent] (any node in the tree). Awaits a few frames; returns the image.
static func render(
	parent: Node, overlay: PlaytraceHeatmapOverlay, scene_path: String, rect: Rect2, zoom: float
) -> Image:
	zoom = minf(zoom, MAX_SIDE / maxf(rect.size.x, rect.size.y))
	var vp := SubViewport.new()
	vp.size = Vector2i((rect.size * zoom).ceil())
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	var level: Node = load(scene_path).instantiate()
	level.process_mode = Node.PROCESS_MODE_DISABLED  # a snapshot: nothing moves
	for cam: Node in level.find_children("*", "Camera2D", true, false):
		cam.free()  # a camera would replace our canvas transform and misalign the layers
	vp.add_child(level)
	var layer := CanvasLayer.new()  # not moved by the canvas transform, like the editor overlay control
	var target := Control.new()
	target.size = Vector2(vp.size)
	layer.add_child(target)
	vp.add_child(layer)
	parent.add_child(vp)
	var xform := PlaytraceOverlayTransform.canvas_transform(zoom, rect.position)
	vp.canvas_transform = xform  # needs the viewport in the tree
	overlay.draw(target, xform, 0.4)
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	overlay.release(target)
	vp.queue_free()
	return image


## The world rect worth exporting for [param overlay]: the heatmap and all markers, plus a margin.
static func level_rect(overlay: PlaytraceHeatmapOverlay) -> Rect2:
	var r := overlay.texture_rect
	for points: PackedVector2Array in [overlay.data.deaths, overlay.data.stuck_points, overlay.data.quit_points]:
		for p: Vector2 in points:
			r = r.expand(p) if r.has_area() else Rect2(p, Vector2.ZERO)
	return r.grow(32.0)
