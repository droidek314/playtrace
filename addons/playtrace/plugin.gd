@tool
extends EditorPlugin
## Editor entry point for Playtrace.
##
## Registers the [code]Playtrace[/code] autoload when the plugin is enabled and removes it
## when disabled. The dock and the viewport overlay are added here in later milestones (WS-C).

const AUTOLOAD_NAME := "Playtrace"
const AUTOLOAD_PATH := "res://addons/playtrace/runtime/playtrace.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
