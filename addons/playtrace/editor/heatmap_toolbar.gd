@tool
class_name PlaytraceHeatmapToolbar
extends HBoxContainer
## Minimal M3 controls in the 2D editor toolbar: show/hide, opacity, kernel radius, palette, reload.
##
## Replaced by the Layers tab of the dock in M4. Uses only built-in controls, so it takes the editor theme.

var _overlay: PlaytraceHeatmapOverlay
var _status := Label.new()


## Connects the controls to [param overlay] and builds them.
func setup(overlay: PlaytraceHeatmapOverlay) -> void:
	_overlay = overlay
	add_child(VSeparator.new())

	var show := CheckButton.new()
	show.text = "Playtrace"
	show.button_pressed = overlay.enabled
	show.tooltip_text = "Show playtest heatmap and deaths for this scene"
	show.toggled.connect(func(on: bool) -> void: overlay.enabled = on)
	add_child(show)

	_add_slider("Opacity", 0.0, 100.0, overlay.opacity * 100.0, func(v: float) -> void: overlay.opacity = v / 100.0)
	_add_slider("Radius", 4.0, 128.0, overlay.kernel_radius_px, func(v: float) -> void: overlay.kernel_radius_px = v)

	var pal := OptionButton.new()
	for n: String in PlaytraceHeatmapPalette.NAMES:
		pal.add_item(n)
	pal.selected = overlay.palette
	pal.tooltip_text = "Heatmap colours"
	pal.item_selected.connect(func(i: int) -> void: overlay.palette = i)
	add_child(pal)

	var reload := Button.new()
	reload.flat = true
	reload.tooltip_text = "Reload sessions"
	reload.icon = EditorInterface.get_editor_theme().get_icon(&"Reload", &"EditorIcons")
	reload.pressed.connect(overlay.reload)
	add_child(reload)

	add_child(_status)
	overlay.changed.connect(_update_status)
	_update_status()


func _add_slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var l := Label.new()
	l.text = label
	add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.custom_minimum_size.x = 80.0
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = label
	s.value_changed.connect(on_change)
	add_child(s)


func _update_status() -> void:
	if _overlay.level.is_empty():
		_status.text = ""
	else:
		_status.text = "%d sessions · %d deaths" % [_overlay.session_count, _overlay.deaths.size()]
