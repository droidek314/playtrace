class_name PlaytraceSettings
extends RefCounted
## Project settings keys and their defaults (contract 6.3).
##
## Runtime and editor read settings through these constants only.

## "auto" (default) or "manual".
const SETUP_MODE := "playtrace/setup/mode"
## Auto-detect the player.
const AUTO_PLAYER := "playtrace/auto/player"
## Auto-detect levels from the current scene.
const AUTO_LEVELS := "playtrace/auto/levels"
## Auto-detect deaths.
const AUTO_DEATHS := "playtrace/auto/deaths"
## Record in release exports too.
const RECORDING_ENABLED_IN_RELEASE := "playtrace/recording/enabled_in_release"
## Seconds between position samples.
const POS_INTERVAL_S := "playtrace/recording/pos_interval_s"
## Minimum movement in pixels before a new position sample is written.
const POS_MIN_DISTANCE_PX := "playtrace/recording/pos_min_distance_px"
## Movement radius in pixels that still counts as stuck.
const STUCK_RADIUS_PX := "playtrace/stuck/radius_px"
## Seconds inside the radius before a stuck event is written.
const STUCK_SECONDS := "playtrace/stuck/seconds"
## Enable the in-game feedback panel.
const FEEDBACK_ENABLED := "playtrace/feedback/enabled"
## Key that opens the feedback panel.
const FEEDBACK_KEY := "playtrace/feedback/key"
## Upload server URL; empty means local only.
const SERVER_URL := "playtrace/server/url"
## Ingest key for uploads.
const SERVER_INGEST_KEY := "playtrace/server/ingest_key"
## Game id written in session headers; defaults to the project name.
const GAME_ID := "playtrace/game_id"


## Returns every key with its default value. GAME_ID defaults to the project name.
static func defaults() -> Dictionary:
	return {
		SETUP_MODE: "auto",
		AUTO_PLAYER: true,
		AUTO_LEVELS: true,
		AUTO_DEATHS: true,
		RECORDING_ENABLED_IN_RELEASE: false,
		POS_INTERVAL_S: 0.2,
		POS_MIN_DISTANCE_PX: 2.0,
		STUCK_RADIUS_PX: 16.0,
		STUCK_SECONDS: 8.0,
		FEEDBACK_ENABLED: false,
		FEEDBACK_KEY: "F8",
		SERVER_URL: "",
		SERVER_INGEST_KEY: "",
		GAME_ID: str(ProjectSettings.get_setting("application/config/name", "")),
	}


## Registers every key that is missing from ProjectSettings with its default, so it shows in the editor.
## Existing values are kept. Does not save project.godot; the editor saves it.
static func register_defaults() -> void:
	var d := defaults()
	for key: String in d:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, d[key])
		ProjectSettings.set_initial_value(key, d[key])
		ProjectSettings.set_as_basic(key, true)
	ProjectSettings.add_property_info(
		{"name": SETUP_MODE, "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": "auto,manual"}
	)


## Returns the current value of [param key], or its default if it is not set.
static func get_value(key: String) -> Variant:
	return ProjectSettings.get_setting(key, defaults().get(key))
