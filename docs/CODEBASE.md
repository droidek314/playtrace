# Codebase tour

A file-by-file guide for contributors. For how the parts fit together, see [ARCHITECTURE.md](ARCHITECTURE.md). For the frozen interfaces, see [CONTRACTS.md](CONTRACTS.md).

## Where to start reading

1. [`addons/playtrace/shared/schema.gd`](../addons/playtrace/shared/schema.gd): the event types.
2. [`addons/playtrace/shared/session_reader.gd`](../addons/playtrace/shared/session_reader.gd) and [`session.gd`](../addons/playtrace/shared/session.gd): how a session file becomes data.
3. [`tools/session_generator.gd`](../tools/session_generator.gd): what a realistic session looks like.

## Top level

| Path | What it is |
| --- | --- |
| `project.godot` | The repo root is a Godot project (D-005). It is used for development, tests and the demo. |
| `.godot-version` | The Godot version CI tests against. |
| `addons/playtrace/` | The plugin: the only folder users copy into their game. |
| `addons/gdUnit4/` | Vendored test framework (D-009). Do not edit. |
| `demo/` | The sandbox level used by tests and the demo. |
| `tools/` | The session generator and its ground truth. Not shipped to users. |
| `tests/` | GdUnit4 suites and frozen fixtures. See [TESTING.md](TESTING.md). |
| `server/` | Self-hostable ASP.NET Core server. See [SERVER.md](SERVER.md) and [SELF_HOSTING.md](SELF_HOSTING.md). |
| `docs/` | All documentation. |

## `addons/playtrace/`

Three folders with a strict rule: `runtime/` and `shared/` must never reference editor-only classes, because they run inside exported games.

| File | Purpose |
| --- | --- |
| `plugin.cfg`, `plugin.gd` | Editor entry point. Enabling the plugin registers the `Playtrace` autoload; disabling it removes the autoload. |
| `runtime/playtrace.gd` | The `Playtrace` autoload. It has no `class_name` (D-006). It runs one `_step()` per frame: it checks for a pending death, follows scene changes (auto levels), finds the player (throttled to every 0.5 s while missing), samples positions on a fixed 0.2 s schedule, feeds the stuck detector, and flushes every 5 s. The public methods are the manual API. The internal `_configure()` takes hooks for tests. |
| `runtime/session_writer.gd` | `PlaytraceSessionWriter`: buffers JSON lines and writes + flushes them on `flush()`. |
| `runtime/stuck_detector.gd` | `PlaytraceStuckDetector`: anchor point + radius; reports one stuck period with its total unpaused time. |
| `shared/schema.gd` | `PlaytraceSchema`: schema version, event type names and the default sessions directory. Use these constants instead of string literals. |
| `shared/settings.gd` | `PlaytraceSettings`: every project settings key, `defaults()`, `register_defaults()` (adds missing keys to Project Settings) and `get_value(key)`. |
| `shared/session.gd` | `PlaytraceSession`: one session in memory (`header`, `events`, `warnings`) plus helpers: `events_of_type()`, `levels()`, `duration_ms()`, `outcome()`. |
| `shared/session_reader.gd` | `PlaytraceSessionReader`: `read_file(path)` never fails. It skips corrupt lines with one warning per file and ignores unknown event types. `list_sessions(dir)` returns sorted `.jsonl` paths. |
| `editor/level_data.gd` | `PlaytraceLevelData`: loads sessions with the reader and keeps the `pos` / `death` events recorded in the edited scene's level. |
| `editor/density_grid.gd` | `PlaytraceDensityGrid`: Gaussian density grid computed on `WorkerThreadPool`. Pure math; see [HOW_IT_WORKS.md](HOW_IT_WORKS.md). |
| `editor/heatmap_palette.gd` | `PlaytraceHeatmapPalette`: magma-like and viridis gradients; turns a grid into a transparent RGBA image. |
| `editor/overlay_transform.gd` | `PlaytraceOverlayTransform`: world → viewport-pixel mapping from the editor's canvas transform. |
| `editor/heatmap_overlay.gd` | `PlaytraceHeatmapOverlay`: layer state (opacity, palette, radius), background recompute, and drawing of the heatmap and death marks. |
| `editor/heatmap_toolbar.gd` | `PlaytraceHeatmapToolbar`: the M3 controls in the 2D editor toolbar. The full dock arrives in M4. |

### How `outcome()` decides

It walks the events backwards and returns `"completed"` or `"quit"` for whichever of `level_complete` / `quit` came last. If there is neither, it returns `"unknown"`, which is also the result for a crashed session whose final line was cut off.

## `tools/`

| File | Purpose |
| --- | --- |
| `planted.json` | Ground truth: positions of the planted problems in the sandbox level. |
| `session_generator.gd` | `PlaytraceSessionGenerator`: `generate(seed, count, level)` returns session id → file text; `write(...)` saves the files. Deterministic per seed. |
| `generate_sessions.gd` | Command-line wrapper (contract 6.5). |

## `demo/`

| File | Purpose |
| --- | --- |
| `sandbox.tscn` | Small 2D level, 2048×512 px: ground, spikes, a hard step, a dead-end branch and a sealed hidden room. The player is a `CharacterBody2D` in group `player`. |
| `player.gd` | Minimal platformer controls. It contains no Playtrace code, to show plug-and-play detection. |
| `spikes.gd` | Reloads the level on touch, which Playtrace auto-detects as a death. |
| `exit.gd` | Calls `Playtrace.complete()` if the autoload exists, then restarts the level. |

## How to add a new event type

1. Add a constant to `shared/schema.gd`.
2. Add it to `KNOWN_TYPES` in `shared/session_reader.gd`. The T02 round-trip test fails until the recorder can write it.
3. Document it in sections 5 and 6 of the spec and in `docs/CONTRACTS.md`. A new type is a compatible change, so the schema number stays the same.
4. Write it from the runtime and add a round-trip test (T02).
