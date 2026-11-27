@tool
class_name PlaytraceInsights
extends RefCounted
## The Insights list for one level: top death hotspots, the largest stuck zone, the most common quit
## point and never-visited floors. Pure and thread-safe; the overlay computes it with the heatmap.
##
## How each is found:
## - Death hotspots: deaths are grouped with [PlaytraceMarkerClusters] at [constant HOTSPOT_PX] and ranked by
##   count. For the top 3 we count deaths per session: the share of players who died there, and the share
##   who died there 3 or more times (shown when it is at least [constant REPEAT_SHARE]).
## - Stuck zone: stuck events grouped the same way, ranked by total stuck seconds.
## - Quit point: quit events grouped the same way, ranked by count.
## - Never visited: the top edges of the level's solid shapes are floors a player could stand on
##   ([PlaytraceLevelSurfaces]). Along each floor, the movement density one [constant STAND_HEIGHT_PX] above
##   it is sampled every cell; runs where it stays under [constant VISITED_SHARE] of the colour scale
##   ([member PlaytraceDensityGrid.norm_value]) for at least [constant MIN_UNVISITED_PX] are reported,
##   longest first.

## Grouping distance for hotspots, stuck zones and quit points, in world px.
const HOTSPOT_PX := 48.0
## A hotspot says "died here 3+ times" when at least this share of players did.
const REPEAT_SHARE := 0.1
## Height above a floor where a standing player's centre is, in world px.
const STAND_HEIGHT_PX := 16.0
## Density below this share of the colour scale counts as not visited.
const VISITED_SHARE := 0.01
## Shortest floor stretch reported as never visited, in world px.
const MIN_UNVISITED_PX := 64.0


## Computes the insights of [param data] (one level, filtered sessions), using the movement [param grid]
## and the level's floor [param surfaces]. Returns dictionaries
## [code]{kind, title, detail, pos, rect, count, sessions}[/code] in display order;
## [code]kind[/code] is "death", "stuck", "quit" or "unvisited".
static func compute(data: PlaytraceLevelData, grid: PlaytraceDensityGrid, surfaces: Array[Rect2]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var players := maxi(data.session_count, 1)
	for c: Dictionary in PlaytraceMarkerClusters.cluster(data.deaths, HOTSPOT_PX).slice(0, 3):
		out.append(death_hotspot(data, c))
	var stuck := PlaytraceMarkerClusters.cluster(data.stuck_points, HOTSPOT_PX, data.stuck_seconds)
	stuck.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	if not stuck.is_empty():
		var c: Dictionary = stuck[0]
		var sessions := _sessions_of(data.stuck_session, c.members)
		out.append(
			_insight(
				"stuck",
				"Largest stuck zone: %d s stuck in total" % roundi(c.weight),
				"%d times, %d %% of players" % [c.count, _pct(sessions.size(), players)],
				c,
				sessions
			)
		)
	var quits := PlaytraceMarkerClusters.cluster(data.quit_points, HOTSPOT_PX)
	if not quits.is_empty():
		var c: Dictionary = quits[0]
		out.append(
			_insight(
				"quit",
				"Most common quit point: %d %% of quits" % _pct(c.count, data.quit_points.size()),
				"%d players quit here" % c.count,
				c,
				_sessions_of(data.quit_session, c.members)
			)
		)
	for r: Rect2 in unvisited_floors(grid, surfaces).slice(0, 3):
		var c := {"pos": r.get_center(), "count": 0}
		var item := _insight("unvisited", "Never visited: %d px of floor" % roundi(r.size.x), "", c, PackedInt32Array())
		item["detail"] = "No player stood on this floor"
		item["rect"] = r
		out.append(item)
	return out


## The insight of death cluster [param c] (from [method PlaytraceMarkerClusters.cluster] on data.deaths).
static func death_hotspot(data: PlaytraceLevelData, c: Dictionary) -> Dictionary:
	var players := maxi(data.session_count, 1)
	var per_session := {}
	for i: int in c.members:
		var s := data.death_session[i]
		per_session[s] = per_session.get(s, 0) + 1
	var repeat := 0
	for s: int in per_session:
		if per_session[s] >= 3:
			repeat += 1
	var title := "%d %% of players died here" % _pct(per_session.size(), players)
	if float(repeat) / players >= REPEAT_SHARE:
		title = "%d %% of players died here 3+ times" % _pct(repeat, players)
	var sessions := PackedInt32Array(per_session.keys())
	sessions.sort()
	return _insight("death", title, "%d deaths" % c.count, c, sessions)


## Floor stretches nobody stood on: world rects [code]STAND_HEIGHT_PX * 2[/code] high on top of the floors,
## longest first. Empty without a grid.
static func unvisited_floors(grid: PlaytraceDensityGrid, surfaces: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if grid.width == 0:
		return out
	var limit := grid.norm_value * VISITED_SHARE
	var step := grid.cell_size
	for s: Rect2 in surfaces:
		var y := s.position.y - STAND_HEIGHT_PX
		var run_start := NAN
		var x := s.position.x + step * 0.5
		while x <= s.end.x:
			var cold := grid.value_at(Vector2(x, y)) < limit
			if cold and is_nan(run_start):
				run_start = x - step * 0.5
			var last := x + step > s.end.x
			if not is_nan(run_start) and (not cold or last):
				var run_end := (x + step * 0.5) if cold else (x - step * 0.5)
				run_end = minf(run_end, s.end.x)
				if run_end - run_start >= MIN_UNVISITED_PX:
					out.append(
						Rect2(
							run_start, s.position.y - 2.0 * STAND_HEIGHT_PX, run_end - run_start, 2.0 * STAND_HEIGHT_PX
						)
					)
				run_start = NAN
			x += step
	out.sort_custom(
		func(a: Rect2, b: Rect2) -> bool:
			return a.size.x > b.size.x or (a.size.x == b.size.x and a.position < b.position)
	)
	return out


## Seconds of movement density within [param radius] of [param pos], divided by [param players]:
## the average time a player spent there (the popover's "average time spent").
static func time_near(grid: PlaytraceDensityGrid, pos: Vector2, radius: float, players: int) -> float:
	if grid.width == 0:
		return 0.0
	var lo := grid.cell_of(pos - Vector2(radius, radius))
	var hi := grid.cell_of(pos + Vector2(radius, radius))
	var total := 0.0
	for cy in range(maxi(lo.y, 0), mini(hi.y, grid.height - 1) + 1):
		for cx in range(maxi(lo.x, 0), mini(hi.x, grid.width - 1) + 1):
			var centre := grid.origin + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * grid.cell_size
			if centre.distance_to(pos) <= radius:
				total += grid.values[cy * grid.width + cx]
	return total / maxi(players, 1)


static func _insight(
	kind: String, title: String, detail: String, c: Dictionary, sessions: PackedInt32Array
) -> Dictionary:
	var r := HOTSPOT_PX * 0.5
	return {
		"kind": kind,
		"title": title,
		"detail": detail,
		"pos": c.pos,
		"rect": Rect2(c.pos - Vector2(r, r), Vector2(r, r) * 2.0),
		"count": c.count,
		"sessions": sessions,
	}


static func _sessions_of(session_of: PackedInt32Array, members: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	for i: int in members:
		seen[session_of[i]] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


static func _pct(part: int, whole: int) -> int:
	return roundi(100.0 * part / maxi(whole, 1))
