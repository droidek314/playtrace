@tool
class_name PlaytraceMarkerClusters
extends RefCounted
## Groups nearby markers (deaths, quits, stuck events) so that zoomed out they draw as one numbered badge.
##
## How it works: markers are hashed into square cells of [param cell] world pixels (the overlay passes a
## fixed screen distance divided by the zoom, so clusters merge as you zoom out and split as you zoom
## in). Then neighbouring cells whose marker centres are closer than one cell are joined (union-find),
## so a group that straddles a cell border is not split in two. Each group becomes one cluster at the
## mean position of its markers. Linear in the number of markers, deterministic, and every marker ends up
## in exactly one cluster, so the badge counts add up to the number of markers (T24).

const _NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


## Clusters [param points] with cell size [param cell] (world px). [param weights] (optional, same size)
## adds up per cluster, for example stuck seconds. Returns an array of
## [code]{pos: Vector2, count: int, weight: float, members: PackedInt32Array}[/code], largest first.
static func cluster(points: PackedVector2Array, cell: float, weights := PackedFloat64Array()) -> Array[Dictionary]:
	var inv := 1.0 / maxf(cell, 0.001)
	var cells := {}  # Vector2i -> PackedInt32Array of member indices
	for i in points.size():
		var key := Vector2i((points[i] * inv).floor())
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(i)
	var keys: Array = cells.keys()
	var index := {}
	var centres := PackedVector2Array()
	for k in keys.size():
		index[keys[k]] = k
		centres.append(_mean(points, cells[keys[k]]))
	var parent := PackedInt32Array()
	parent.resize(keys.size())
	for k in keys.size():
		parent[k] = k
	for k in keys.size():
		for d: Vector2i in _NEIGHBOURS:
			var other: Variant = index.get(keys[k] + d)
			if other != null and centres[k].distance_to(centres[other]) < cell:
				var ra := _root(parent, k)
				var rb := _root(parent, other)
				if ra != rb:
					parent[maxi(ra, rb)] = mini(ra, rb)
	var groups := {}
	for k in keys.size():
		var r := _root(parent, k)
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		groups[r].append_array(cells[keys[k]])
	var clusters: Array[Dictionary] = []
	for r: int in groups:
		var members: PackedInt32Array = groups[r]
		members.sort()
		var w := 0.0
		for i: int in members:
			if i < weights.size():
				w += weights[i]
		clusters.append({"pos": _mean(points, members), "count": members.size(), "weight": w, "members": members})
	clusters.sort_custom(
		func(x: Dictionary, y: Dictionary) -> bool:
			return x.count > y.count or (x.count == y.count and x.members[0] < y.members[0])
	)
	return clusters


static func _mean(points: PackedVector2Array, members: PackedInt32Array) -> Vector2:
	var sum := Vector2.ZERO
	for i: int in members:
		sum += points[i]
	return sum / members.size()


static func _root(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		k = parent[k]
	return k
