@tool
class_name PlaytraceOverlayTransform
extends RefCounted
## World -> overlay (screen) mapping for the 2D editor viewport.
##
## The 2D editor shows the edited scene through a canvas transform: scale by the zoom, then
## translate by the pan. The editor's own gizmos are drawn on the viewport overlay control with this
## same transform, which is [code]EditorInterface.get_editor_viewport_2d().global_canvas_transform[/code].
## Playtrace reads that transform on every redraw, so the layers follow pan and zoom exactly.
## Pure math, unit-tested headless (T20).


## Builds the canvas transform the 2D editor uses for [param zoom] and a view offset
## [param view_offset] (the world point shown at the overlay's top-left corner).
static func canvas_transform(zoom: float, view_offset: Vector2) -> Transform2D:
	return Transform2D(0.0, Vector2(zoom, zoom), 0.0, -view_offset * zoom)


## Maps world position [param p] to overlay pixels.
static func world_to_overlay(xform: Transform2D, p: Vector2) -> Vector2:
	return xform * p


## Maps an axis-aligned world rect to overlay pixels (the editor transform has no rotation).
static func world_rect_to_overlay(xform: Transform2D, rect: Rect2) -> Rect2:
	return xform * rect
