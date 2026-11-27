# Manual integration

Playtrace works with no code at all (plug-and-play). This page is for when you want control: your player isn't a `CharacterBody2D`, your levels aren't separate scenes, or deaths don't remove the player node.

You can mix both styles. The **takeover rule** means the first explicit call for a feature switches off auto-detection of that feature for the rest of the run, so nothing is counted twice.

## The API

`Playtrace` is an autoload, so every script can call it. All calls are safe no-ops when recording is off, so you never need to check before calling.

### `Playtrace.track(node: Node2D)`

Tells Playtrace which node is the player. Turns off auto player detection.

```gdscript
# player.gd
extends CharacterBody2D

func _ready() -> void:
	Playtrace.track(self)
```

Call it again whenever a new player node is created, for example after a respawn that instantiates a new player.

### `Playtrace.death(cause: String = "")`

Records a death at the tracked player's position. Turns off auto deaths. An empty cause is written as `"manual"`.

```gdscript
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("spikes"):
		Playtrace.death("spikes")
		respawn()
```

### `Playtrace.level(id: String)`

Sets the current level id. Turns off auto levels (which use the scene's file path). Use it when one scene holds several levels or areas.

```gdscript
func _on_area_changed(area_name: String) -> void:
	Playtrace.level("world/" + area_name)
```

Each call writes `level_exit` for the previous level and `level_enter` for the new one. Calling it again with the same id counts as re-entering the level.

### `Playtrace.event(name: StringName, data: Dictionary = {})`

Records a custom event with any JSON-compatible data.

```gdscript
Playtrace.event(&"opened_door", {"door": "red"})
```

### `Playtrace.checkpoint(name: String)`

Records reaching a checkpoint at the player's position.

```gdscript
func _on_checkpoint_body_entered(_body: Node2D) -> void:
	Playtrace.checkpoint("before_boss")
```

### `Playtrace.complete()`

Records that the current level was completed. A session whose last `level_complete` / `quit` is a `level_complete` counts as **completed**.

```gdscript
func _on_goal_reached() -> void:
	Playtrace.complete()
```

### `Playtrace.is_recording() -> bool`

True while a session is being recorded.

```gdscript
$RecordingDot.visible = Playtrace.is_recording()
```

### `Playtrace.get_detection_report() -> Dictionary`

What Playtrace detected, in the same shape as the `detection` field of the session header:

```gdscript
var report := Playtrace.get_detection_report()
# {"mode": "auto", "player": "Player (CharacterBody2D)", "deaths": "node_removal",
#  "levels": "scene", "warnings": []}
for warning: String in report["warnings"]:
	print("Playtrace setup problem: ", warning)
```

### Signals

```gdscript
func _ready() -> void:
	Playtrace.session_started.connect(func(id: String) -> void: print("recording ", id))
	Playtrace.session_finished.connect(func(id: String, path: String) -> void: print("saved ", path))
```

## Project settings

All settings are under **Project → Project Settings → Playtrace** (turn on **Advanced Settings** if you don't see them). They are registered with their defaults when the plugin is enabled.

| Setting | Default | Effect |
| --- | --- | --- |
| `playtrace/setup/mode` | `auto` | `auto` guesses player, levels and deaths. `manual` records only your explicit calls. |
| `playtrace/auto/player` | `true` | Auto-detect the player (in `auto` mode). |
| `playtrace/auto/levels` | `true` | Use the current scene's file path as the level id. |
| `playtrace/auto/deaths` | `true` | Count player removal and quick same-scene reloads as deaths. |
| `playtrace/recording/enabled_in_release` | `false` | Also record in release exports. Editor runs and debug exports always record. |
| `playtrace/recording/pos_interval_s` | `0.2` | How often the player position is sampled. |
| `playtrace/recording/pos_min_distance_px` | `2.0` | A position is only written if the player moved more than this since the last one. |
| `playtrace/stuck/radius_px` | `16.0` | Staying within this radius counts as standing in one place. |
| `playtrace/stuck/seconds` | `8.0` | Unpaused seconds in one place before it counts as stuck. |
| `playtrace/feedback/enabled` | `false` | In-game feedback panel (arrives in M7). |
| `playtrace/feedback/key` | `F8` | Key that opens the feedback panel. |
| `playtrace/server/url` | `""` | Upload server. Empty means sessions stay on this machine. |
| `playtrace/server/ingest_key` | `""` | The project's ingest key for uploads. |
| `playtrace/game_id` | project name | Game name written in every session. |

## How auto-detection decides

| Feature | Rule |
| --- | --- |
| Player | The first `Node2D` in group `player` inside the current scene. If there is none, the first `CharacterBody2D` in the scene. Found again after every scene change. |
| Levels | The current scene's `scene_file_path`, checked every frame. A new scene instance, including a reload of the same scene, writes `level_exit` + `level_enter`. |
| Deaths | The tracked player leaves the scene tree while its scene keeps running, **or** the same scene is reloaded within 1 s. Switching to a different scene is not a death. |
| Stuck | The player stays within 16 px of one spot for 8 s of unpaused time. The event is written when they move on (or die, change level or quit), with the total seconds. |
| Quit | The window is closed, the game exits, or a web tab stays hidden for more than 30 s. |

Each run prints one line to the Output panel, for example:

```
Playtrace: tracking Player (CharacterBody2D) · deaths: node_removal · levels: scene
```

## Setup health warnings and how to fix them

The editor dock's **Setup** tab shows these warnings. The codes are constants in `PlaytraceSchema`.

| Warning | What it means | Fix |
| --- | --- | --- |
| `player_not_found` | No node in group `player` and no `CharacterBody2D` in the scene. | Add your player node to group `player` (Node → Groups), or call `Playtrace.track(self)` in the player's `_ready()`. |
| `player_never_moved` | The tracked node never moved more than 2 px in a session, so it's probably the wrong node. | Put the right node in group `player`, or call `Playtrace.track()` on the node that actually moves. |
| `reloads_without_deaths` | A level was re-entered 3 or more times across sessions but no deaths were recorded. Your game probably "kills" the player without removing it. | Call `Playtrace.death("cause")` where the player dies. |

## Turning recording off

- Release exports don't record unless `playtrace/recording/enabled_in_release` is on.
- Command-line runs (`godot --script ...`) and test runners never record.
- To stop recording in a debug build, disable the plugin, or remove the `Playtrace` autoload.
