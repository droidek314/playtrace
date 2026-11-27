@tool
extends EditorPlugin
## Editor entry point for Playtrace.
##
## Registers the [code]Playtrace[/code] autoload when the plugin is enabled and removes it when
## disabled. While loaded, it owns the layers over the 2D viewport ([PlaytraceHeatmapOverlay]), the
## Playtrace bottom panel ([PlaytraceDock]), the switch in the 2D toolbar ([PlaytraceHeatmapToolbar]) and
## the marker popover. Settings persist in [PlaytraceEditorConfig].
## The overlay uses the force-draw variant of the canvas overlay hook (D-027), so it is drawn whatever
## node is selected. Clicks on markers come from the viewport control's [signal Control.gui_input].

const AUTOLOAD_NAME := "Playtrace"
const AUTOLOAD_PATH := "res://addons/playtrace/runtime/playtrace.gd"

var _config: PlaytraceEditorConfig
var _overlay: PlaytraceHeatmapOverlay
var _toolbar: PlaytraceHeatmapToolbar
var _dock: PlaytraceDock
var _popover: PopupPanel
var _viewport_control: Control
var _two_d_visible := true
var _was_playing := false
var _time := 0.0


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	PlaytraceSettings.register_defaults()
	_config = PlaytraceEditorConfig.new()
	_overlay = PlaytraceHeatmapOverlay.new()
	_overlay.font = EditorInterface.get_editor_theme().get_font(&"bold", &"EditorFonts")
	_overlay.enabled = _config.get_value("layers/enabled")
	_overlay.changed.connect(update_overlays)
	_dock = PlaytraceDock.new()
	_dock.setup(_overlay, _config)
	_dock.focus_requested.connect(_focus)
	_dock.save_png_requested.connect(_save_png)
	add_control_to_bottom_panel(_dock, "Playtrace")
	_toolbar = PlaytraceHeatmapToolbar.new()
	_toolbar.setup(_overlay)
	_toolbar.toggled_layers.connect(
		func(on: bool) -> void:
			_config.set_value("layers/enabled", on)
			_config.save()
	)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_popover = PopupPanel.new()
	EditorInterface.get_base_control().add_child(_popover)
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	scene_saved.connect(func(_path: String) -> void: _on_scene_changed(EditorInterface.get_edited_scene_root()))
	main_screen_changed.connect(func(screen: String) -> void: _two_d_visible = screen == "2D")
	_on_scene_changed(EditorInterface.get_edited_scene_root())
	if not _config.get_value("setup/wizard_done"):
		make_bottom_panel_item_visible(_dock)
		_dock.show_setup()


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	if is_instance_valid(_viewport_control) and _viewport_control.gui_input.is_connected(_on_viewport_input):
		_viewport_control.gui_input.disconnect(_on_viewport_input)
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	remove_control_from_bottom_panel(_dock)
	_dock.queue_free()
	_popover.queue_free()
	_overlay.shutdown()
	_config.save()


func _process(delta: float) -> void:
	_time += delta
	if _two_d_visible and _overlay.animating():
		update_overlays()  # stuck rings pulse only while they are on screen
	var playing := EditorInterface.is_playing_scene()
	if _was_playing and not playing:
		_overlay.reload()  # a playtest just ended: pick up its session file
	_was_playing = playing


func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	if viewport_control != _viewport_control:
		_viewport_control = viewport_control
		viewport_control.gui_input.connect(_on_viewport_input)
	_overlay.draw(viewport_control, EditorInterface.get_editor_viewport_2d().global_canvas_transform, _time)


func _on_viewport_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var h := _overlay.hit(click.position)
	if not h.is_empty():
		_show_popover(_overlay.describe(h), _viewport_control.get_screen_position() + click.position)


func _show_popover(info: Dictionary, at: Vector2) -> void:
	for c: Node in _popover.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = info.title
	title.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font(&"bold", &"EditorFonts"))
	box.add_child(title)
	for line: String in info.lines:
		var l := Label.new()
		l.text = line
		box.add_child(l)
	var replay := Button.new()
	replay.text = "Replay these sessions"
	replay.disabled = true
	replay.tooltip_text = "Path replay arrives in M5 (%d sessions)" % (info.sessions as PackedInt32Array).size()
	box.add_child(replay)
	_popover.add_child(box)
	_popover.popup(Rect2i(Vector2i(at) + Vector2i(12, 12), Vector2i.ZERO))
	_popover.reset_size()


func _focus(pos: Vector2) -> void:
	EditorInterface.set_main_screen_editor("2D")
	for cie: Node in EditorInterface.get_base_control().find_children("*", "CanvasItemEditor", true, false):
		cie.call("center_at", pos)


func _save_png() -> void:
	if _overlay.level.is_empty() or _overlay.texture == null:
		push_warning("Playtrace: open a 2D scene with recorded sessions before saving a PNG")
		return
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.png", "PNG image")
	dialog.current_file = _overlay.level.get_file().get_basename() + "_playtrace.png"
	dialog.file_selected.connect(
		func(path: String) -> void:
			var image := await PlaytraceOverlayExport.render(
				self, _overlay, _overlay.level, PlaytraceOverlayExport.level_rect(_overlay), 1.0
			)
			var err := image.save_png(path)
			if err != OK:
				push_warning("Playtrace: cannot save %s (error %d)" % [path, err])
			else:
				print("Playtrace: saved overlay to ", path)
			dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_file_dialog()


func _on_scene_changed(root: Node) -> void:
	_overlay.surfaces = PlaytraceLevelSurfaces.from_scene(root)
	_overlay.set_level(root.scene_file_path if root != null else "")
