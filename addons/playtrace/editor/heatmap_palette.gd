@tool
class_name PlaytraceHeatmapPalette
extends RefCounted
## Colour maps for the heatmap and the step that turns a [PlaytraceDensityGrid] into an [Image].
##
## Pipeline (spec 3, 7.1): density -> [Gradient] lookup table -> RGBA [Image]; the overlay uploads it
## to an [ImageTexture] drawn with linear filtering. Low density fades to fully transparent, and the
## top colour is not fully opaque, so the level stays readable (spec 7.3).

## Magma-like: transparent -> indigo -> magenta -> orange -> warm white. The default.
const MAGMA := 0
## Viridis-like: transparent -> purple -> blue -> green -> yellow. Colour-blind friendly.
const VIRIDIS := 1
## Display names, indexed by palette id.
const NAMES: Array[String] = ["Magma", "Viridis"]
## Density is shown as (value / norm) ^ GAMMA, clamped at 1, where norm is the grid's 99th percentile
## ([member PlaytraceDensityGrid.norm_value]). The curve keeps thin paths visible next to hot spots.
const GAMMA := 0.5

const _LUT_SIZE := 1024


## Returns the [Gradient] for palette [param id] ([constant MAGMA] or [constant VIRIDIS]).
static func gradient(id: int) -> Gradient:
	var g := Gradient.new()
	if id == VIRIDIS:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.6, 0.82, 1.0])
		g.colors = PackedColorArray(
			[
				Color(0.267, 0.005, 0.329, 0.0),
				Color(0.267, 0.005, 0.329, 0.55),
				Color(0.231, 0.322, 0.545, 0.75),
				Color(0.129, 0.569, 0.549, 0.85),
				Color(0.369, 0.788, 0.384, 0.9),
				Color(0.993, 0.906, 0.144, 0.95),
			]
		)
	else:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.38, 0.68, 1.0])
		g.colors = PackedColorArray(
			[
				Color(0.23, 0.06, 0.44, 0.0),
				Color(0.23, 0.06, 0.44, 0.55),
				Color(0.72, 0.21, 0.47, 0.8),
				Color(0.98, 0.53, 0.32, 0.9),
				Color(0.99, 0.96, 0.82, 0.95),
			]
		)
	return g


## Colours [param grid] with palette [param id] into an RGBA8 image, one pixel per cell.
## Safe to call from a worker thread. Returns null for an empty grid.
static func colorize(grid: PlaytraceDensityGrid, id: int) -> Image:
	if grid.width == 0 or grid.height == 0 or grid.norm_value <= 0.0:
		return null
	var g := gradient(id)
	var lut := PackedByteArray()
	lut.resize(_LUT_SIZE * 4)
	for i in _LUT_SIZE:
		var c := g.sample(pow(float(i) / float(_LUT_SIZE - 1), GAMMA))
		lut[i * 4] = c.r8
		lut[i * 4 + 1] = c.g8
		lut[i * 4 + 2] = c.b8
		lut[i * 4 + 3] = c.a8
	# Empty cells get the first colour at alpha 0 (not black), so linear filtering leaves no dark fringe.
	var base := Image.create_empty(grid.width, grid.height, false, Image.FORMAT_RGBA8)
	base.fill(g.sample(0.0))
	var data := base.get_data()
	var scale := float(_LUT_SIZE - 1) / grid.norm_value
	var top := (_LUT_SIZE - 1) * 4
	var values := grid.values
	for i in values.size():
		var v := values[i]
		if v <= 0.0:
			continue
		var o := mini(int(v * scale) * 4, top)
		var d := i * 4
		data[d] = lut[o]
		data[d + 1] = lut[o + 1]
		data[d + 2] = lut[o + 2]
		data[d + 3] = lut[o + 3]
	return Image.create_from_data(grid.width, grid.height, false, Image.FORMAT_RGBA8, data)
