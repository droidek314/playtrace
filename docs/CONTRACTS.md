# Playtrace contracts

These are the frozen interfaces every part of Playtrace codes against: the session file format, the GDScript API, the project settings and the server HTTP API.

**Source of truth:** sections 5 and 6 of [PLAYTRACE_SPEC.md](../PLAYTRACE_SPEC.md), copied here verbatim. The server API is also available as an OpenAPI 3.1 file: [openapi.yaml](openapi.yaml).

## How to change a contract

Contracts are frozen after Phase 0. A change must, in the same commit or PR:

1. Edit section 5 or 6 of `PLAYTRACE_SPEC.md` **and** this file (and `openapi.yaml` for HTTP changes).
2. Update the shared fixtures in `tests/fixtures/`.
3. Say clearly in the commit/PR description that it changes a contract, and add a line to [DECISIONS.md](DECISIONS.md).

## Versioning and compatibility

- **Session files** carry `"schema": 1` in the header. Adding a new event `type` or a new optional field is a compatible change and keeps the schema number: readers already ignore unknown types and fields. Renaming or removing a field, changing a field's type or meaning, or changing `t`/`p` units is a breaking change and bumps `schema`. Readers must keep reading every older schema number they ever supported.
- **GDScript API (6.1, 6.2):** adding a method, signal or an optional parameter with a default is compatible. Removing or renaming anything, or changing a parameter or return type, is breaking and only happens in a new major version of the plugin (semver).
- **Settings keys (6.3):** new keys are compatible. Keys are never renamed; a removed key is ignored when read.
- **HTTP API (6.4):** all paths are under `/v1`. New endpoints, new optional query parameters and new response fields are compatible; clients ignore unknown response fields. A breaking change goes to `/v2`, and `/v1` stays available for at least one minor plugin release.

## 5. Data model (session file format, schema v1)

Each session = one JSON Lines file. Line 1 is the header (`session_start`), then one event per line.

```jsonl
{"schema":1,"type":"session_start","session":"7f3c9a2e-...","game":"my-platformer","build":"0.3.1","godot":"4.5.1","platform":"Web","started_utc":"2026-12-02T18:04:11Z","detection":{"mode":"auto","player":"Player (CharacterBody2D)","deaths":"node_removal","levels":"scene"}}
{"t":0,"type":"level_enter","level":"res://levels/level_2.tscn"}
{"t":200,"type":"pos","p":[128.0,412.5,0]}
{"t":18450,"type":"death","p":[912.0,388.0,0],"data":{"cause":"spikes"}}
{"t":61200,"type":"stuck","p":[1540.0,300.0,0],"data":{"seconds":12.4}}
{"t":95010,"type":"quit","p":[1544.0,302.0,0]}
```

| type | Written when | Fields |
| --- | --- | --- |
| `session_start` | recorder start (header) | `schema`, `session` (UUID v4), `game`, `build`, `godot`, `platform`, `started_utc`, `detection` (`mode`, `player`, `deaths`, `levels`, `warnings`; D-029) |
| `level_enter` / `level_exit` | level changes (auto or `level()`) | `level` |
| `pos` | every 0.2 s if moved > 2 px (configurable) | `p` |
| `death` | auto-detected or `death()` | `p`, `data.cause` (`"auto"` if detected) |
| `stuck` | auto-detected | `p`, `data.seconds` |
| `checkpoint` | `checkpoint(name)` | `p`, `data.name` |
| `level_complete` | `complete()` | `p` |
| `quit` | quit detected | `p` (last known) |
| `custom` | `event(name, data)` | `name`, `data` |
| `feedback` | feedback panel submitted | `p`, `data.text`, `data.screenshot` (file name, optional) |

Rules:
- `t` = integer milliseconds since session start from a monotonic clock (`Time.get_ticks_msec()` offset).
- `p` is always `[x, y, z]` floats, world/global coordinates of the tracked node; 2D writes `z = 0`.
- Readers ignore unknown `type`s and unknown fields (forward compatibility). Corrupt lines are skipped with one warning per file.
- Writer appends and flushes every 5 s and on `level_exit` / quit. A crash loses at most 5 s.
- Screenshots stored next to the session: `user://playtrace/sessions/<session_id>/<n>.jpg` (max 1280 px wide).

## 6. Frozen contracts (Phase 0 produces these; everyone codes against them)

### 6.1 GDScript public API (autoload `Playtrace`, file `runtime/playtrace.gd`)

The script has **no** `class_name` (it would clash with the autoload name; D-006).

```gdscript
# All methods are safe no-ops when recording is off.
func track(node: Node2D) -> void                      # manual player; disables auto player
func death(cause: String = "") -> void                # manual death; disables auto deaths; empty cause is written as "manual" (D-007)
func level(id: String) -> void                        # manual level id; disables auto levels
func event(name: StringName, data: Dictionary = {}) -> void
func checkpoint(name: String) -> void
func complete() -> void
func is_recording() -> bool
func get_detection_report() -> Dictionary             # same shape as header.detection + "warnings": Array[String]
signal session_started(session_id: String)
signal session_finished(session_id: String, path: String)
```

### 6.2 Shared reader API (`shared/session_reader.gd`, `class_name PlaytraceSessionReader`; session type in `shared/session.gd`, `class_name PlaytraceSession`)

```gdscript
static func read_file(path: String) -> PlaytraceSession       # never throws; bad lines skipped
static func list_sessions(dir: String = "user://playtrace/sessions") -> Array[String]
# PlaytraceSession: header: Dictionary, events: Array[Dictionary], warnings: Array[String]
# helpers: events_of_type(type: String) -> Array[Dictionary], levels() -> Array[String],
#          duration_ms() -> int, outcome() -> String  ("completed" | "quit" | "unknown")
```

### 6.3 Project settings keys (`shared/settings.gd` defines constants + defaults)

| Key | Type | Default |
| --- | --- | --- |
| `playtrace/setup/mode` | String `auto`/`manual` | `auto` |
| `playtrace/auto/player` | bool | `true` |
| `playtrace/auto/levels` | bool | `true` |
| `playtrace/auto/deaths` | bool | `true` |
| `playtrace/recording/enabled_in_release` | bool | `false` |
| `playtrace/recording/pos_interval_s` | float | `0.2` |
| `playtrace/recording/pos_min_distance_px` | float | `2.0` |
| `playtrace/stuck/radius_px` | float | `16.0` |
| `playtrace/stuck/seconds` | float | `8.0` |
| `playtrace/feedback/enabled` | bool | `false` |
| `playtrace/feedback/key` | String | `F8` |
| `playtrace/server/url` | String | `""` (empty = local only) |
| `playtrace/server/ingest_key` | String | `""` |
| `playtrace/game_id` | String | project name |

Editor-only settings (read key, layer state) are stored in `res://.playtrace/settings.cfg` (git-ignorable), never in exported builds.

### 6.4 Server HTTP API (`docs/CONTRACTS.md` also contains an OpenAPI 3.1 file `docs/openapi.yaml`)

| Method | Path | Auth | Body / query | Responses |
| --- | --- | --- | --- | --- |
| POST | `/v1/sessions` | `Authorization: Bearer <ingest_key>` | gzipped JSONL, `Content-Encoding: gzip`, max 2 MB | `201` created, `200` duplicate (idempotent by session id), `400` invalid, `401`, `413`, `429` |
| GET | `/v1/sessions?since=<cursor>&level=&build=&limit=` | `Bearer <read_key>` | — | `200` `{ "items":[{id, level(s), build, started_utc, duration_ms, outcome, deaths}], "next": "<cursor>" }` |
| GET | `/v1/sessions/{id}` | `Bearer <read_key>` | — | `200` gzipped JSONL, `404` |
| GET | `/health` | none | — | `200` `{"status":"ok"}` |

- Keys are per project. `dotnet Playtrace.Server.dll create-project <name>` prints a new ingest key and read key (stored hashed).
- Ingest keys cannot read; read keys cannot write.
- CORS: allow `POST /v1/sessions` from any origin (web builds); GET endpoints require the read key and are not meant for browsers.
- Rate limit: 60 uploads/min per ingest key (configurable env var).
- Client IPs are used only for rate limiting and never stored.

### 6.5 Session generator CLI (`tools/generate_sessions.gd`)

```
godot --headless --script tools/generate_sessions.gd -- --seed 1 --count 200 --level res://demo/sandbox.tscn --out user://playtrace/sessions
```
Planted features (fixed positions defined in `tools/planted.json`, used by tests as ground truth):
`death_cluster`, `stuck_zone`, `quit_point`, `unvisited_area`, `backtrack_loop`. Same seed → byte-identical output.
