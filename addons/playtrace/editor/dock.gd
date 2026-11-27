@tool
class_name PlaytraceDock
extends VBoxContainer
## The Playtrace bottom panel (spec 7.2): Sessions, Layers, Insights, Setup and Server tabs.
##
## Built from plain editor controls so it takes the editor theme, fonts and icons. It edits the
## [PlaytraceHeatmapOverlay] (layers, filters) and stores every choice in [PlaytraceEditorConfig].
## Lists refresh when the overlay emits [signal PlaytraceHeatmapOverlay.data_changed].

## Asks the plugin to centre the 2D editor on world position [param pos].
signal focus_requested(pos: Vector2)
## Asks the plugin to export the current overlay as a PNG.
signal save_png_requested

const OUTCOMES: Array[String] = ["completed", "quit", "unknown"]
const _DATE := "^\\d{4}-\\d{2}-\\d{2}$"

var _overlay: PlaytraceHeatmapOverlay
var _config: PlaytraceEditorConfig
var _theme: Theme
var _tabs := TabContainer.new()
var _save_timer := Timer.new()
var _date_re := RegEx.create_from_string(_DATE)
# Sessions tab
var _level_opt := OptionButton.new()
var _build_opt := OptionButton.new()
var _outcome_opt := OptionButton.new()
var _from := LineEdit.new()
var _to := LineEdit.new()
var _count := Label.new()
var _sessions := Tree.new()
# Insights tab
var _insights := Tree.new()
var _insights_note := Label.new()
# Setup tab
var _setup := VBoxContainer.new()
var _fix_dialog := AcceptDialog.new()


## Builds the tabs for [param overlay], with saved choices from [param config].
func setup(overlay: PlaytraceHeatmapOverlay, config: PlaytraceEditorConfig) -> void:
	_overlay = overlay
	_config = config
	_theme = EditorInterface.get_editor_theme()
	name = "Playtrace"
	custom_minimum_size.y = 220
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_config.save)
	add_child(_save_timer)
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tabs)
	_tabs.add_child(_build_sessions())
	_tabs.add_child(_build_layers())
	_tabs.add_child(_build_insights())
	_tabs.add_child(_build_setup())
	_tabs.add_child(_build_server())
	_tabs.current_tab = clampi(_config.get_value("dock/tab"), 0, _tabs.get_tab_count() - 1)
	_tabs.tab_changed.connect(func(t: int) -> void: _store("dock/tab", t))
	_fix_dialog.title = "Fix setup"
	overlay.data_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if is_instance_valid(_fix_dialog):
		_fix_dialog.queue_free()


## Opens the Setup tab (used on first enable to show the wizard).
func show_setup() -> void:
	_tabs.current_tab = 3


func _icon(icon_name: String) -> Texture2D:
	return _theme.get_icon(icon_name, &"EditorIcons") if _theme.has_icon(icon_name, &"EditorIcons") else null


func _store(key: String, value: Variant) -> void:
	_config.set_value(key, value)
	_save_timer.start()


# --- Sessions -------------------------------------------------------------------------------------


func _build_sessions() -> Control:
	var box := VBoxContainer.new()
	box.name = "Sessions"
	var bar := HFlowContainer.new()  # wraps on narrow panels instead of widening the editor
	box.add_child(bar)
	for pair: Array in [[_level_opt, "Level"], [_build_opt, "Build"], [_outcome_opt, "Outcome"]]:
		var opt: OptionButton = pair[0]
		opt.fit_to_longest_item = false
		opt.clip_text = true
		opt.custom_minimum_size.x = 150 * EditorInterface.get_editor_scale()
		var l := Label.new()
		l.text = pair[1]
		bar.add_child(l)
		bar.add_child(pair[0])
		(pair[0] as OptionButton).item_selected.connect(func(_i: int) -> void: _apply_filter())
	for edit: LineEdit in [_from, _to]:
		edit.placeholder_text = "from YYYY-MM-DD" if edit == _from else "to YYYY-MM-DD"
		edit.custom_minimum_size.x = 130 * EditorInterface.get_editor_scale()
		edit.text_submitted.connect(func(_t: String) -> void: _apply_filter())
		edit.focus_exited.connect(_apply_filter)
		bar.add_child(edit)
	var clear := Button.new()
	clear.text = "Clear filters"
	clear.pressed.connect(_clear_filters)
	bar.add_child(clear)
	var reload := Button.new()
	reload.icon = _icon("Reload")
	reload.tooltip_text = "Read the session files again"
	reload.pressed.connect(_overlay.reload)
	bar.add_child(reload)
	bar.add_child(_count)
	_sessions.columns = 6
	_sessions.column_titles_visible = true
	_sessions.hide_root = true
	_sessions.size_flags_vertical = SIZE_EXPAND_FILL
	var scale := EditorInterface.get_editor_scale()
	var widths := [180, 90, 80, 70, 110, 200]
	for i in 6:
		_sessions.set_column_title(i, ["Date", "Build", "Duration", "Deaths", "Outcome", "Levels"][i])
		_sessions.set_column_expand(i, i == 5)
		_sessions.set_column_custom_minimum_width(i, int(widths[i] * scale))
		_sessions.set_column_clip_content(i, false)
	box.add_child(_sessions)
	var f := _config.filter()
	_from.text = f.date_from
	_to.text = f.date_to
	_overlay.filter = f
	return box


func _fill_option(opt: OptionButton, all_label: String, values: Array[String], current: String) -> void:
	opt.clear()
	opt.add_item(all_label)
	opt.set_item_metadata(0, "")
	for v: String in values:
		opt.add_item(v.get_file() if v.begins_with("res://") else v)
		opt.set_item_metadata(opt.item_count - 1, v)
		opt.set_item_tooltip(opt.item_count - 1, v)
		if v == current:
			opt.select(opt.item_count - 1)
	if current.is_empty() or not values.has(current):
		opt.select(0)
		if not current.is_empty():
			opt.add_item(current + " (no sessions)")
			opt.set_item_metadata(opt.item_count - 1, current)
			opt.select(opt.item_count - 1)


func _current_filter() -> Dictionary:
	var f := PlaytraceSessionLibrary.NO_FILTER.duplicate()
	f.level = str(_level_opt.get_selected_metadata()) if _level_opt.selected >= 0 else ""
	f.build = str(_build_opt.get_selected_metadata()) if _build_opt.selected >= 0 else ""
	f.outcome = str(_outcome_opt.get_selected_metadata()) if _outcome_opt.selected >= 0 else ""
	for pair: Array in [[_from, "date_from"], [_to, "date_to"]]:
		var t: String = (pair[0] as LineEdit).text.strip_edges()
		f[pair[1]] = t if _date_re.search(t) else ""
		(pair[0] as LineEdit).modulate = Color.WHITE if t.is_empty() or _date_re.search(t) else Color(1, 0.6, 0.6)
	return f


func _apply_filter() -> void:
	var f := _current_filter()
	if f == _overlay.filter:
		return
	for k: String in f:
		_config.set_value("filters/" + k, f[k])
	_save_timer.start()
	_overlay.filter = f
	_fill_sessions()


func _clear_filters() -> void:
	_from.text = ""
	_to.text = ""
	for opt: OptionButton in [_level_opt, _build_opt, _outcome_opt]:
		opt.select(0)
	_apply_filter()


func _fill_sessions() -> void:
	_sessions.clear()
	var root := _sessions.create_item()
	var shown := PlaytraceSessionLibrary.filter(_overlay.records, _overlay.filter)
	for r: Dictionary in shown:
		var s: Dictionary = r.summary
		var row := _sessions.create_item(root)
		var secs := int(s.duration_ms) / 1000
		var levels: Array = s.levels
		row.set_text(0, str(s.started_utc).replace("T", " ").substr(0, 16))
		row.set_text(1, s.build)
		row.set_text(2, "%d:%02d" % [secs / 60, secs % 60])
		row.set_text(3, str(s.deaths))
		row.set_text(4, s.outcome)
		row.set_text(5, ", ".join(levels.map(func(l: String) -> String: return l.get_file())))
		row.set_tooltip_text(0, str(s.path))
		row.set_tooltip_text(5, ", ".join(levels))
	_count.text = "%d of %d sessions" % [shown.size(), _overlay.records.size()]
	if _overlay.records.is_empty():
		_count.text = "No sessions yet: run the game (F5) to record one"


# --- Layers ---------------------------------------------------------------------------------------


func _build_layers() -> Control:
	var grid := GridContainer.new()
	grid.name = "Layers"
	grid.columns = 2
	for item: Array in [
		["layers/heatmap", "Movement heatmap", "show_heatmap"],
		["layers/deaths", "Deaths", "show_deaths"],
		["layers/stuck", "Stuck zones", "show_stuck"],
		["layers/quits", "Quit points", "show_quits"],
	]:
		var check := CheckBox.new()
		check.text = item[1]
		check.button_pressed = _config.get_value(item[0])
		_overlay.set(item[2], check.button_pressed)
		check.toggled.connect(
			func(on: bool) -> void:
				_overlay.set(item[2], on)
				_store(item[0], on)
		)
		grid.add_child(check)
		grid.add_child(Control.new())
	_slider(
		grid, "Opacity", 0, 100, _config.get_value("layers/opacity") * 100.0, "%", "layers/opacity", 0.01, "opacity"
	)
	_slider(
		grid,
		"Kernel radius",
		4,
		128,
		_config.get_value("layers/radius_px"),
		" px",
		"layers/radius_px",
		1.0,
		"kernel_radius_px"
	)
	var pal_label := Label.new()
	pal_label.text = "Palette"
	grid.add_child(pal_label)
	var pal := OptionButton.new()
	for n: String in PlaytraceHeatmapPalette.NAMES:
		pal.add_item(n)
	pal.selected = _config.get_value("layers/palette")
	_overlay.palette = pal.selected
	pal.item_selected.connect(
		func(i: int) -> void:
			_overlay.palette = i
			_store("layers/palette", i)
	)
	grid.add_child(pal)
	grid.add_child(Control.new())
	var save := Button.new()
	save.text = "Save PNG..."
	save.icon = _icon("ImageTexture")
	save.tooltip_text = "Export the level with the current layers as a PNG"
	save.pressed.connect(save_png_requested.emit)
	grid.add_child(save)
	return grid


func _slider(
	grid: GridContainer,
	label: String,
	lo: float,
	hi: float,
	value: float,
	unit: String,
	key: String,
	scale: float,
	prop: String
) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.custom_minimum_size.x = 200
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size.x = 56
	var apply := func(x: float) -> void:
		v.text = "%d%s" % [roundi(x), unit]
		_overlay.set(prop, x * scale)
		_store(key, x * scale)
	s.value = value
	v.text = "%d%s" % [roundi(value), unit]
	_overlay.set(prop, value * scale)
	s.value_changed.connect(apply)
	row.add_child(s)
	row.add_child(v)
	grid.add_child(row)


# --- Insights -------------------------------------------------------------------------------------


func _build_insights() -> Control:
	var box := VBoxContainer.new()
	box.name = "Insights"
	_insights_note.text = "Click an insight to show it in the 2D view."
	box.add_child(_insights_note)
	_insights.columns = 2
	_insights.hide_root = true
	_insights.size_flags_vertical = SIZE_EXPAND_FILL
	_insights.set_column_expand(0, true)
	_insights.set_column_expand(1, true)
	_insights.set_column_custom_minimum_width(0, int(360 * EditorInterface.get_editor_scale()))
	_insights.item_selected.connect(_on_insight_selected)
	box.add_child(_insights)
	return box


func _fill_insights() -> void:
	_insights.clear()
	var root := _insights.create_item()
	var icons := {"death": "StatusError", "stuck": "Time", "quit": "Back", "unvisited": "GuiVisibilityHidden"}
	for i: Dictionary in _overlay.insights:
		var row := _insights.create_item(root)
		row.set_icon(0, _icon(icons[i.kind]))
		row.set_text(0, i.title)
		row.set_text(1, i.detail)
		row.set_metadata(0, i.pos)
	if _overlay.level.is_empty():
		_insights_note.text = "Open a 2D scene to see insights for it."
	elif _overlay.data.session_count == 0:
		_insights_note.text = "No sessions for this scene yet (or none match the filters)."
	else:
		_insights_note.text = (
			"%d sessions of %s. Click an insight to show it in the 2D view."
			% [_overlay.data.session_count, _overlay.level.get_file()]
		)


func _on_insight_selected() -> void:
	var row := _insights.get_selected()
	if row != null:
		focus_requested.emit(row.get_metadata(0))


# --- Setup ----------------------------------------------------------------------------------------


func _build_setup() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Setup"
	_setup.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_setup)
	return scroll


func _fill_setup() -> void:
	for c: Node in _setup.get_children():
		c.queue_free()
	if not _config.get_value("setup/wizard_done"):
		_wizard()
		return
	var mode := str(ProjectSettings.get_setting(PlaytraceSettings.SETUP_MODE, "auto"))
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Setup mode: " + ("Manual (explicit calls)" if mode == "manual" else "Plug-and-play (no code)")
	head.add_child(title)
	var change := Button.new()
	change.text = "Change..."
	change.pressed.connect(
		func() -> void:
			_store("setup/wizard_done", false)
			_fill_setup()
	)
	head.add_child(change)
	_setup.add_child(head)
	if mode == "manual":
		_checklist()
	_health_card()


func _wizard() -> void:
	var q := Label.new()
	q.text = "How do you want to record playtests?"
	_setup.add_child(q)
	for choice: Array in [
		["auto", "Plug-and-play", "No code. Playtrace finds the player, levels, deaths, stuck moments and quits."],
		["manual", "Manual", "You call Playtrace.track(), death(), level() ... yourself. A checklist below helps."],
	]:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = choice[1]
		b.custom_minimum_size.x = 140
		b.pressed.connect(_choose_mode.bind(choice[0]))
		row.add_child(b)
		var d := Label.new()
		d.text = choice[2]
		row.add_child(d)
		_setup.add_child(row)


func _choose_mode(mode: String) -> void:
	ProjectSettings.set_setting(PlaytraceSettings.SETUP_MODE, mode)
	ProjectSettings.save()
	_store("setup/wizard_done", true)
	_fill_setup()


func _checklist() -> void:
	var seen := PlaytraceSetupHealth.seen_types(_overlay.records)
	var title := Label.new()
	title.text = "Manual checklist (ticks itself when a recorded session contains the event):"
	_setup.add_child(title)
	for item: Dictionary in PlaytraceSetupHealth.CHECKLIST:
		var row := HBoxContainer.new()
		var tick := CheckBox.new()
		tick.text = item.call
		tick.button_pressed = seen.has(item.event)
		tick.disabled = true
		tick.custom_minimum_size.x = 130
		row.add_child(tick)
		row.add_child(_code_field(item.code))
		row.add_child(_copy_button(item.code))
		var where := Label.new()
		where.text = item.where
		row.add_child(where)
		_setup.add_child(row)


func _health_card() -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Setup health"
	title.add_theme_font_override("font", _theme.get_font(&"bold", &"EditorFonts"))
	box.add_child(title)
	var lines := PlaytraceSetupHealth.card(_overlay.records)
	if lines.is_empty():
		var none := Label.new()
		none.text = "No sessions yet. Run your game once (F5); this card then shows what Playtrace detected."
		box.add_child(none)
	for line: Dictionary in lines:
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = _icon("StatusSuccess" if line.ok else "StatusWarning")
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(icon)
		var text := Label.new()
		text.text = "%s: %s" % [line.label, line.value]
		text.modulate = Color(0.6, 1.0, 0.6) if line.ok else Color(1.0, 0.85, 0.4)
		row.add_child(text)
		if not str(line.warning).is_empty():
			var fix := Button.new()
			fix.text = "Fix"
			fix.pressed.connect(_show_fix.bind(line.warning))
			row.add_child(fix)
		box.add_child(row)
	for code: String in PlaytraceSetupHealth.warnings(_overlay.records):
		var w := Label.new()
		w.text = "Warning: " + code
		w.modulate = Color(1.0, 0.85, 0.4)
		box.add_child(w)
	_setup.add_child(panel)


func _show_fix(code: String) -> void:
	var fix: Dictionary = PlaytraceSetupHealth.FIXES[code]
	for c: Node in _fix_dialog.get_children():
		if c is VBoxContainer:
			c.queue_free()
	var box := VBoxContainer.new()
	var text := Label.new()
	text.text = fix.text
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_child(_code_field(fix.code))
	row.add_child(_copy_button(fix.code))
	box.add_child(row)
	var where := Label.new()
	where.text = "Where: " + fix.where
	box.add_child(where)
	_fix_dialog.add_child(box)
	if _fix_dialog.get_parent() == null:
		EditorInterface.popup_dialog_centered(_fix_dialog, Vector2i(560, 160))
	else:
		_fix_dialog.popup_centered(Vector2i(560, 160))


func _code_field(code: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = code
	e.editable = false
	e.custom_minimum_size.x = 300
	e.add_theme_font_override("font", _theme.get_font(&"source", &"EditorFonts"))
	return e


func _copy_button(code: String) -> Button:
	var b := Button.new()
	b.icon = _icon("ActionCopy")
	b.tooltip_text = "Copy"
	b.pressed.connect(func() -> void: DisplayServer.clipboard_set(code))
	return b


# --- Server ---------------------------------------------------------------------------------------


func _build_server() -> Control:
	var box := VBoxContainer.new()
	box.name = "Server"
	var note := Label.new()
	note.text = "Remote sessions arrive in M6."
	box.add_child(note)
	for placeholder: String in ["Server URL", "Read key"]:
		var e := LineEdit.new()
		e.placeholder_text = placeholder
		e.editable = false
		e.custom_minimum_size.x = 320
		box.add_child(e)
	var fetch := Button.new()
	fetch.text = "Fetch"
	fetch.disabled = true
	box.add_child(fetch)
	return box


# --- Refresh --------------------------------------------------------------------------------------


func _refresh() -> void:
	var f := _overlay.filter
	_fill_option(_level_opt, "All levels", PlaytraceSessionLibrary.values_of(_overlay.records, "levels"), f.level)
	_fill_option(_build_opt, "All builds", PlaytraceSessionLibrary.values_of(_overlay.records, "build"), f.build)
	_fill_option(_outcome_opt, "All outcomes", OUTCOMES, f.outcome)
	_fill_sessions()
	_fill_insights()
	_fill_setup()
