@tool
class_name PlaytraceHeatmapToolbar
extends HBoxContainer
## The small Playtrace switch in the 2D editor toolbar: shows or hides all layers and says how many
## sessions are shown. Everything else lives in the Playtrace bottom panel ([PlaytraceDock]).

## Emitted when the switch is flipped (the plugin stores it).
signal toggled_layers(on: bool)

var _overlay: PlaytraceHeatmapOverlay
var _switch := CheckButton.new()
var _status := Label.new()


## Connects the switch to [param overlay].
func setup(overlay: PlaytraceHeatmapOverlay) -> void:
	_overlay = overlay
	add_child(VSeparator.new())
	_switch.text = "Playtrace"
	_switch.button_pressed = overlay.enabled
	_switch.tooltip_text = "Show playtest layers for this scene (settings: Playtrace panel at the bottom)"
	_switch.toggled.connect(
		func(on: bool) -> void:
			overlay.enabled = on
			toggled_layers.emit(on)
	)
	add_child(_switch)
	add_child(_status)
	overlay.changed.connect(_update_status)
	overlay.data_changed.connect(_update_status)
	_update_status()


func _update_status() -> void:
	_switch.set_pressed_no_signal(_overlay.enabled)
	if _overlay.level.is_empty():
		_status.text = ""
	elif _overlay.busy and _overlay.records.is_empty():
		_status.text = "loading..."
	else:
		_status.text = "%d sessions · %d deaths" % [_overlay.data.session_count, _overlay.data.deaths.size()]
