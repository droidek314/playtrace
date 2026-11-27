@tool
class_name PlaytraceDensityGrid
extends RefCounted
## Smoothed 2D density of world-space points: the data behind the movement heatmap.
##
## Pure math with no editor dependency, so it is unit-tested headless (T16, T21).
## [method build] can be called from any thread; the overlay runs it on the [WorkerThreadPool].
##
## How it works (density estimate with a Gaussian kernel):
## [codeblock]
## D(c) = sum over points p of  G(c - p),   G(d) = exp(-|d|^2 / (2 sigma^2)) / Z
## [/codeblock]
## Z normalises the sampled kernel so it sums to 1, so the grid's total mass equals the point count.
## Instead of adding a 2D kernel per point (points x taps^2), we:
## 1. bin every point into its cell: one add per point, sessions split over worker threads,
##    one partial grid per thread, summed after;
## 2. blur the counts with a separable Gaussian: a 1D kernel along rows, then along columns.
##    The 2D Gaussian is the product of two 1D ones, so this is exact and costs cells x taps.
##    Both passes skip empty cells (levels are mostly empty) and run in row bands on worker threads.
## The cell size is sigma / 2, so the kernel is always 13 taps wide whatever the radius; the
## texture's linear filtering hides the cells. The grid is padded by 3 sigma + 1 cell so no mass is lost.
## Every parallel step writes only to arrays it owns (packed arrays are copy-on-write, so sharing
## one for writing across threads is unsafe in GDScript).

## Largest grid we build (cells). Bigger levels get bigger cells.
const MAX_CELLS := 1 << 20
## Cells per sigma. Two keeps the blur cheap while linear filtering keeps it smooth.
const CELLS_PER_SIGMA := 2.0

## World position of the grid's top-left corner.
var origin := Vector2.ZERO
## World size of one square cell.
var cell_size := 1.0
## Grid width in cells.
var width := 0
## Grid height in cells.
var height := 0
## Density per cell, row-major ([code]y * width + x[/code]).
var values := PackedFloat32Array()
## Largest value in [member values].
var max_value := 0.0

# Work shared with the parallel steps. Threads only read these; each writes its own _parts slot.
var _sets: Array[PackedVector2Array] = []
var _src := PackedFloat32Array()
var _kernel := PackedFloat32Array()
var _parts: Array[PackedFloat32Array] = []
var _jobs := 1


## Builds the density of [param point_sets] (one array per session) with kernel sigma [param sigma_px].
## [param bounds] is a world rect holding the points (points outside are ignored); empty = computed
## from the points. The grid covers it plus padding for the kernel.
static func build(
	point_sets: Array[PackedVector2Array], sigma_px: float, bounds: Rect2 = Rect2()
) -> PlaytraceDensityGrid:
	var grid := PlaytraceDensityGrid.new()
	sigma_px = maxf(sigma_px, 0.5)
	if bounds == Rect2():
		if _count(point_sets) == 0:
			return grid
		bounds = points_bounds(point_sets)
	var cell := _cell_size(bounds.grow(3.0 * sigma_px), sigma_px)
	bounds = bounds.grow(3.0 * sigma_px + cell)
	grid.cell_size = _cell_size(bounds, sigma_px)
	grid.origin = bounds.position
	grid.width = maxi(1, ceili(bounds.size.x / grid.cell_size))
	grid.height = maxi(1, ceili(bounds.size.y / grid.cell_size))
	grid._jobs = clampi(OS.get_processor_count(), 1, 16)
	grid._bin(point_sets)
	grid._blur(sigma_px / grid.cell_size)
	return grid


## Returns the smallest rect containing every point (zero rect when there are none).
static func points_bounds(point_sets: Array[PackedVector2Array]) -> Rect2:
	var first := true
	var r := Rect2()
	for pts: PackedVector2Array in point_sets:
		for p: Vector2 in pts:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


## World rect covered by the grid (where the heatmap texture is drawn).
func world_rect() -> Rect2:
	return Rect2(origin, Vector2(width, height) * cell_size)


## Cell containing world position [param p] (may be outside the grid).
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell_size), floori((p.y - origin.y) / cell_size))


## Density at world position [param p]; 0 outside the grid.
func value_at(p: Vector2) -> float:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return 0.0
	return values[c.y * width + c.x]


## World position of the centre of the densest cell.
func peak_position() -> Vector2:
	var best := 0
	for i in values.size():
		if values[i] > values[best]:
			best = i
	return origin + (Vector2(best % maxi(width, 1), best / maxi(width, 1)) + Vector2(0.5, 0.5)) * cell_size


## Sum of all cells (equals the number of points inside the bounds).
func total() -> float:
	var s := 0.0
	for v: float in values:
		s += v
	return s


static func _cell_size(bounds: Rect2, sigma_px: float) -> float:
	return maxf(sigma_px / CELLS_PER_SIGMA, sqrt(bounds.get_area() / MAX_CELLS))


static func _count(point_sets: Array[PackedVector2Array]) -> int:
	var n := 0
	for pts: PackedVector2Array in point_sets:
		n += pts.size()
	return n


# Runs method(i) for i in 0..n-1 on the WorkerThreadPool (inline when n == 1) and waits.
# High priority: the caller is usually itself a pool task waiting on these.
func _parallel(method: Callable, n: int, label: String) -> void:
	_parts.resize(n)
	if n == 1:
		method.call(0)
	else:
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(method, n, -1, true, label))


# Concatenates the row bands in _parts into one grid and frees them.
func _join_bands() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: PackedFloat32Array in _parts:
		out.append_array(part)
	_parts.clear()
	return out


func _band_rows(band: int) -> Vector2i:
	var per := ceili(float(height) / _parts.size())
	return Vector2i(mini(band * per, height), mini((band + 1) * per, height))


func _bin(point_sets: Array[PackedVector2Array]) -> void:
	_sets = point_sets
	_parallel(_bin_chunk, mini(_jobs, maxi(1, point_sets.size())), "Playtrace density binning")
	values = _parts[0]
	for c in range(1, _parts.size()):
		var part := _parts[c]
		for i in values.size():
			values[i] += part[i]
	_parts.clear()
	_sets = []


# Adds 1.0 per point to its cell, for sessions chunk, chunk + n, ... into a private grid.
func _bin_chunk(chunk: int) -> void:
	var local := PackedFloat32Array()
	local.resize(width * height)
	# Transform2D * PackedVector2Array runs in C++: it maps a whole session to cell units at once.
	var to_cells := Transform2D(0.0, Vector2.ONE / cell_size, 0.0, -origin / cell_size)
	var w := width
	var wf := float(width)
	var hf := float(height)
	var n := _parts.size()
	var s := chunk
	while s < _sets.size():
		for c: Vector2 in to_cells * _sets[s]:
			if c.x >= 0.0 and c.y >= 0.0 and c.x < wf and c.y < hf:
				local[int(c.y) * w + int(c.x)] += 1.0
		s += n
	_parts[chunk] = local


func _blur(sigma_cells: float) -> void:
	var r := ceili(3.0 * sigma_cells)
	_kernel.resize(2 * r + 1)
	var ksum := 0.0
	for i in range(-r, r + 1):
		var k := exp(-float(i * i) / (2.0 * sigma_cells * sigma_cells))
		_kernel[i + r] = k
		ksum += k
	for i in _kernel.size():
		_kernel[i] /= ksum
	var bands := mini(_jobs, height)
	_src = values
	_parallel(_blur_rows_band, bands, "Playtrace density blur")
	_src = _join_bands()
	_parallel(_blur_cols_band, bands, "Playtrace density blur")
	values = _join_bands()
	_src = PackedFloat32Array()
	max_value = 0.0
	for v: float in values:
		max_value = maxf(max_value, v)


# Horizontal pass for one band of rows: scatter each non-empty cell along its row.
func _blur_rows_band(band: int) -> void:
	var rows := _band_rows(band)
	var w := width
	var r := (_kernel.size() - 1) / 2
	var kernel := _kernel
	var out := PackedFloat32Array()
	out.resize((rows.y - rows.x) * w)
	for y in range(rows.x, rows.y):
		var src_row := y * w
		var out_row := (y - rows.x) * w
		for x in w:
			var v := _src[src_row + x]
			if v == 0.0:
				continue
			for k in range(maxi(-r, -x), mini(r, w - 1 - x) + 1):
				out[out_row + x + k] += v * kernel[k + r]
	_parts[band] = out


# Vertical pass for one band of output rows: gather the rows within the kernel radius.
func _blur_cols_band(band: int) -> void:
	var rows := _band_rows(band)
	var w := width
	var r := (_kernel.size() - 1) / 2
	var kernel := _kernel
	var out := PackedFloat32Array()
	out.resize((rows.y - rows.x) * w)
	for y in range(rows.x, rows.y):
		var out_row := (y - rows.x) * w
		for k in range(maxi(-r, -y), mini(r, height - 1 - y) + 1):
			var src_row := (y + k) * w
			var kv := kernel[k + r]
			for x in w:
				var v := _src[src_row + x]
				if v != 0.0:
					out[out_row + x] += v * kv
	_parts[band] = out
