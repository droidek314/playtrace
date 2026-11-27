@tool
extends EditorPlugin
## Editor entry point for Playtrace.
##
## Registers the [code]Playtrace[/code] autoload when the plugin is enabled and removes it when
## disabled. While loaded, it draws the heatmap overlay ([PlaytraceHeatmapOverlay]) over the 2D
## viewport for the edited scene and adds its controls ([PlaytraceHeatmapToolbar]) to the 2D toolbar.
## The overlay uses the force-draw variant of the canvas overlay hook, so it is drawn whatever node
## is selected (the plain [code]_forward_canvas_draw_over_viewport()[/code] only runs while this
## plugin handles the selected node).

const AUTOLOAD_NAME := "Playtrace"
const AUTOLOAD_PATH := "res://addons/playtrace/runtime/playtrace.gd"

var _overlay: PlaytraceHeatmapOverlay
var _toolbar: PlaytraceHeatmapToolbar


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	_overlay = PlaytraceHeatmapOverlay.new()
	_overlay.changed.connect(update_overlays)
	_toolbar = PlaytraceHeatmapToolbar.new()
	_toolbar.setup(_overlay)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	_overlay.shutdown()


func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	viewport_control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay.draw(viewport_control, EditorInterface.get_editor_viewport_2d().global_canvas_transform)


func _on_scene_changed(root: Node) -> void:
	_overlay.set_level(root.scene_file_path if root != null else "")
