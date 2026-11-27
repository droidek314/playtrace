@tool
class_name PlaytraceLevelSurfaces
extends RefCounted
## Finds the floors of a 2D level: the top edges of its solid shapes, where a player could stand.
## [PlaytraceInsights] uses them to report never-visited areas.
##
## Supported: [StaticBody2D] / [AnimatableBody2D] with [RectangleShape2D] collision shapes (unrotated), and
## [TileMapLayer] cells whose cell above is empty. Other shapes (polygons, circles, rotated bodies) are
## skipped; their floors are simply not checked. Reads the scene tree, so call it on the main thread.


## Returns the floors under [param root] as world rects of height 0 (position = left end of the top edge).
static func from_scene(root: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if root == null:
		return out
	for node: Node in [root] + root.find_children("*", "", true, false):
		if node is CollisionShape2D and not node.disabled and node.shape is RectangleShape2D:
			var body := node.get_parent()
			if body is StaticBody2D:
				var xf: Transform2D = node.global_transform
				if absf(xf.get_rotation()) < 0.001:
					var size: Vector2 = (node.shape as RectangleShape2D).size * xf.get_scale().abs()
					var top_left := xf.origin - size * 0.5
					out.append(Rect2(top_left, Vector2(size.x, 0)))
		elif node is TileMapLayer:
			out.append_array(_tile_floors(node))
	return out


static func _tile_floors(layer: TileMapLayer) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var used := {}
	for c: Vector2i in layer.get_used_cells():
		used[c] = true
	var cells: Array = used.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var tile := Vector2(layer.tile_set.tile_size) if layer.tile_set else Vector2(16, 16)
	var xf := layer.global_transform
	var run_start := Vector2i.MAX
	var prev := Vector2i.MAX
	for c: Vector2i in cells + [Vector2i.MAX]:
		var floor_cell: bool = c != Vector2i.MAX and not used.has(c + Vector2i.UP)
		var continues := floor_cell and prev != Vector2i.MAX and c == prev + Vector2i.RIGHT
		if prev != Vector2i.MAX and not continues:
			var left := xf * (layer.map_to_local(run_start) - tile * 0.5)
			var right := xf * (layer.map_to_local(prev) + Vector2(tile.x, -tile.y) * 0.5)
			out.append(Rect2(left, Vector2(right.x - left.x, 0)))
			prev = Vector2i.MAX
		if floor_cell:
			if prev == Vector2i.MAX:
				run_start = c
			prev = c
	return out
