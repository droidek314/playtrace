@tool
class_name PlaytraceEditorConfig
extends RefCounted
## Editor-only settings of the dock and the layers, kept in [code]res://.playtrace/settings.cfg[/code]
## (spec 6.3: git-ignorable, never in exported builds).
##
## Values live in one [ConfigFile] section per group. [method get_value] falls back to [constant DEFAULTS],
## so a missing or old file always works. T25 checks a save/load round trip.

## Where the settings are stored.
const PATH := "res://.playtrace/settings.cfg"
## Every setting with its default, as section/key.
const DEFAULTS := {
	"layers/enabled": true,
	"layers/heatmap": true,
	"layers/deaths": true,
	"layers/stuck": true,
	"layers/quits": true,
	"layers/opacity": 0.65,
	"layers/radius_px": 16.0,
	"layers/palette": PlaytraceHeatmapPalette.MAGMA,
	"filters/level": "",
	"filters/build": "",
	"filters/outcome": "",
	"filters/date_from": "",
	"filters/date_to": "",
	"dock/tab": 0,
	"setup/wizard_done": false,
}

var _file := ConfigFile.new()
var _path := PATH


## Loads [param path] if it exists (defaults otherwise).
func _init(path: String = PATH) -> void:
	_path = path
	if FileAccess.file_exists(path):
		_file.load(path)


## Returns the value of [param key] ("section/name"), or its default.
func get_value(key: String) -> Variant:
	var parts := key.split("/")
	return _file.get_value(parts[0], parts[1], DEFAULTS.get(key))


## Sets [param key] ("section/name") to [param value]. Call [method save] to write it.
func set_value(key: String, value: Variant) -> void:
	var parts := key.split("/")
	_file.set_value(parts[0], parts[1], value)


## Writes the settings file, creating its folder. Logs a warning if it cannot.
func save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path.get_base_dir()))
	var err := _file.save(_path)
	if err != OK:
		push_warning("Playtrace: cannot save editor settings to %s (error %d)" % [_path, err])


## The session filter stored in the "filters" section (keys of [constant PlaytraceSessionLibrary.NO_FILTER]).
func filter() -> Dictionary:
	var f := {}
	for k: String in PlaytraceSessionLibrary.NO_FILTER:
		f[k] = str(get_value("filters/" + k))
	return f
