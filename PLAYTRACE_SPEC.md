# Playtrace — Build Specification for AI Agents

> Working title: **Playtrace**. Godot 4 playtest analytics plugin (2D first).
> Spec version: 1.1 · 2026-11-27 · Owner: Edvard Khromov (github.com/droidek314)
> 1.1: Phase 0 clarifications applied inline and listed in section 16. Read section 16 before starting work.

---

## 0. How to use this document (read first)

This file is the single source of truth for building Playtrace. It is written for AI coding agents.

- **You are the main agent (lead).** The person starts only you. You own the whole project and decide when to get help.
- **Use 2–3 agents in total, never more:** you plus at most 2 sub-agents that YOU start yourself (e.g. with your Agent/Task tool). Do not ask the person to start or coordinate other agents.
- **Phase 0 is done by you alone.** Only after M0 is complete and contracts (section 6) are frozen may you start sub-agents.
- **Each sub-agent gets ONE workstream bundle** from section 10, works only inside the directories it owns, and codes against the frozen contracts in section 6. Give it this file, its bundle name, the milestones it must finish, and the instruction to report back with: what was done, test results, and any contract questions.
- **You review and merge** every sub-agent's work: run CI locally, check acceptance criteria, then merge. Sub-agents never merge to `main` themselves.
- If the work in a phase is small or tightly coupled, do it yourself instead of starting a sub-agent. Starting a sub-agent is for clearly separate work, not by default.
- **Contracts (section 6) are frozen after Phase 0.** If a workstream truly needs a contract change, it must: (1) edit section 6 of this file and `docs/CONTRACTS.md`, (2) update the shared fixtures in `tests/fixtures/`, (3) say so clearly in the commit/PR description. Never change a contract silently.
- **A milestone is done** only when every acceptance criterion is checked, all of its tests in section 12 pass, CI is green, and the documentation it touches (section 15) is written and up to date.
- When something is ambiguous, choose the simplest option that satisfies the acceptance criteria, and write the decision in `docs/DECISIONS.md` (one line: date, decision, reason).
- Do not add features listed under Non-goals.

---

## 1. Product summary

Playtrace is a free, open-source (MIT) Godot plugin that shows **where playtesters die, get stuck, get lost and quit — drawn directly over the level inside the Godot editor**. The goal is a tool people really use, not income. v1 optimises for a near-zero setup and visuals good enough to share as a GIF.

**Users:** solo devs and small indie teams making 2D games in Godot 4, running playtests with friends, jam players or itch.io testers.

**Differentiator:** existing tools (GameAnalytics, Aptabase, Talo, Quiver) are number dashboards for live games; Framedash draws heatmaps but requires C# and focuses on performance. Playtrace is GDScript-only, design-focused, and visualises data on the level itself in the editor.

### Goals (v1)

1. Record playtest sessions from a Godot 2D game **with zero code** (plug-and-play), or with explicit calls (manual), or a mix.
2. Show deaths, movement density, stuck zones and quit points as smooth layers over the level in the 2D editor viewport.
3. Replay player paths with a timeline scrubber, many sessions at once.
4. Collect sessions from remote testers, including web builds, via a small self-hostable server.
5. Look native in the Godot editor and good in a 10-second GIF.

### Non-goals (v1) — do NOT build

- 3D visualisation (but the data format stores `[x, y, z]` from day one; 2D writes `z = 0`).
- Non-spatial analytics: funnels, decision trees, UI click maps.
- Procedurally generated level grouping.
- Monetisation / retention / live-ops analytics, user accounts, a web dashboard, any paid tier.

---

## 2. Setup modes: plug-and-play AND manual (both first-class)

### 2.1 Plug-and-play mode (default)

Install → enable plugin → press Play → heatmap with deaths. No code, no scene edits, no required settings.

| Feature | Automatic behaviour | Manual override |
| --- | --- | --- |
| Plugin install | `_enable_plugin()` registers the `Playtrace` autoload via `add_autoload_singleton` | — |
| Player | First node in group `player`; else first `CharacterBody2D` in the current scene; re-resolved on scene change | `Playtrace.track(node)` |
| Levels | Current scene's `scene_file_path`, checked every frame (cheap compare) | `Playtrace.level(id)` |
| Deaths | Tracked node exits the tree (`tree_exiting`) while the scene keeps running, OR the same scene reloads within 1.0 s after the tracked node was alive → `death` at last known position, `cause = "auto"` | `Playtrace.death(cause)` |
| Stuck | Movement < 16 px for ≥ 8 s while `get_tree().paused == false` | thresholds in settings |
| Quit | `NOTIFICATION_WM_CLOSE_REQUEST`, `NOTIFICATION_PREDELETE` of autoload, web `visibilitychange → hidden` for > 30 s | — |
| Recording on/off | ON for runs from the editor and debug exports; OFF in release exports unless `playtrace/recording/enabled_in_release = true` | settings |
| Editor display | Overlay + dock appear automatically when sessions exist for the open scene | — |

### 2.2 Manual mode

- `playtrace/setup/mode` = `"auto"` (default) or `"manual"`. In `manual`, nothing is guessed; only explicit calls are recorded.
- Per-feature switches: `playtrace/auto/player`, `playtrace/auto/levels`, `playtrace/auto/deaths` (all `bool`, default `true`).
- **Takeover rule:** the first explicit call for a feature disables auto-detection of that feature for the rest of the run (e.g. first `Playtrace.death()` disables auto deaths). This guarantees no double counting when mixing.

### 2.3 Guidance (makes manual setup easy)

- **Setup wizard** (dock, first enable): choose Plug-and-play or Manual. Manual shows a checklist of calls with copy buttons for snippets; each item auto-ticks when its event appears in a recorded session.
- **Detection report:** on every run the recorder prints one line to the output log and stores it in the `session_start` header, e.g. `Playtrace: tracking Player (CharacterBody2D) · deaths: node removal · levels: scene`. The dock shows a **Setup health** card: each line green (confirmed) or yellow (guessed / suspicious), with a **Fix** button that shows the exact one line of code and where to put it.
- **Warnings:** player not found; tracked node never moved in a session; level reloaded ≥ 3 times across sessions but 0 deaths recorded.
- **Recipes** in `docs/RECIPES.md`: respawn at checkpoint, co-op (two players), vehicles, one big world split into areas.
- **Safety:** the plugin never crashes or slows the game. All runtime code is wrapped so errors are logged once (`push_warning`) and recording continues or stops cleanly. All API calls are no-ops when recording is off.

---

## 3. Technology stack (fixed — do not substitute without a DECISIONS.md entry)

| Area | Choice |
| --- | --- |
| Engine support | Godot 4.4+ (2D) targeted; only the version in `.godot-version` (4.7.2) is tested in CI. Testing older 4.x versions is a later decision (D-008). |
| Plugin language | GDScript only, static typing everywhere. No C#, no GDExtension. |
| Editor integration | `EditorPlugin`: bottom dock + `_forward_canvas_force_draw_over_viewport()` overlay (D-027). |
| Heatmap compute | CPU density grid, Gaussian kernel, via `WorkerThreadPool`. |
| Heatmap colouring | `Gradient` → `Image` → `ImageTexture`, linear filtering. Default palette magma-like; viridis option. |
| Local storage | JSON Lines, one file per session: `user://playtrace/sessions/<session_id>.jsonl`. Note: a game run from the editor and the editor itself share the same `user://` dir, so local mode needs no transport. |
| Upload | Gzipped JSONL over HTTPS with `HTTPRequest` (works in web exports). On web tab hide, best-effort `fetch(..., {keepalive: true})` via `JavaScriptBridge` (D-017; `sendBeacon` cannot send the auth header). |
| Server | .NET 10 LTS, ASP.NET Core minimal APIs, C#. |
| Database | PostgreSQL + EF Core; events in a `jsonb` column. |
| Deployment | Docker image + `docker compose` (server + Postgres). |
| GDScript tests | GdUnit4 (vendored, pinned in `addons/gdUnit4`, excluded from lint), headless (`godot --headless`). |
| Lint/format | gdtoolkit: `gdlint`, `gdformat --check`. |
| Server tests | xUnit + `WebApplicationFactory` + Testcontainers (PostgreSQL). |
| E2E | Playwright (headless Chromium) against the exported web demo + real server. |
| CI | GitHub Actions. |
| Licence | MIT. |

---

## 4. Architecture

```
 Game build                      Storage                         Godot editor plugin
┌──────────────────────┐      ┌──────────────────────────┐      ┌────────────────────────┐
│ Playtrace autoload   │─────▶│ user://playtrace/sessions│─────▶│ Session reader         │
│ (recorder, detector, │      │ one .jsonl per session   │      │ (local + fetched)      │
│  uploader, feedback) │      └──────────────────────────┘      │          │             │
│                      │      ┌──────────────────────────┐      │          ▼             │
│                      │─────▶│ Server (Docker)          │─────▶│ Heatmap worker         │
└──────────────────────┘ gzip │ ASP.NET Core API         │ read │          │             │
                       upload │   └─▶ PostgreSQL (jsonb) │  key │          ▼             │
                              └──────────────────────────┘      │ Overlay + dock         │
                                                                └────────────────────────┘
```

Hard rule: **`runtime/` must never reference editor-only classes** (`EditorInterface`, `EditorPlugin`, etc.) so it works in exported games. `shared/` is used by both runtime and editor and must also be editor-free.

### 4.1 Repository layout and ownership

```
playtrace/                     # repo root IS the Godot project (D-005)
  project.godot                # [Phase 0]
  addons/gdUnit4/              # vendored test framework, do not edit (D-009)
  addons/playtrace/
    plugin.cfg
    plugin.gd                  # EditorPlugin entry: registers autoload, dock, overlay   [WS-C]
    runtime/                   # Playtrace autoload, recorder, detectors, uploader, feedback panel [WS-A]
    editor/                    # overlay, heatmap worker, dock, wizard, replay, insights  [WS-C]
    shared/                    # schema constants, event types, session reader, settings keys [WS-B]
                               #   session.gd = class_name PlaytraceSession (D-003)
  demo/                        # sandbox level, pre-recorded sessions                      [WS-E]
  tests/
    fixtures/                  # frozen sample sessions (Phase 0)                           [Phase 0]
    golden/                    # golden PNGs for heatmap tests                              [WS-C]
    runtime/  shared/  editor/ # GdUnit4 suites, owned by matching workstream
  tools/                       # session generator, benchmarks                              [WS-B]
  server/
    src/Playtrace.Server/                                                                   [WS-D]
    tests/Playtrace.Server.Tests/                                                           [WS-D]
    Dockerfile
    docker-compose.yml
  e2e/                         # Playwright tests                                           [WS-E]
  docs/                        # CONTRACTS.md, DECISIONS.md, RECIPES.md, SELF_HOSTING.md    [WS-E, contracts: Phase 0]
  .github/workflows/                                                                        [WS-E]
  .godot-version
  README.md                                                                                 [WS-E]
```

---

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
| `session_start` | recorder start (header) | `schema`, `session` (UUID v4), `game`, `build`, `godot`, `platform`, `started_utc`, `detection` |
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

---

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

---

## 7. Features and visual design

Visual quality is a requirement, not polish.

### 7.1 Overlay layers (2D editor viewport)

| Layer | Look | Interaction |
| --- | --- | --- |
| Movement density | Smooth Gaussian heatmap: transparent → indigo → magenta → orange → warm white (magma-like); viridis option | opacity 0–100 %, kernel radius slider |
| Deaths | Small X marks with soft dark outline; cluster into numbered badges when zoomed out | click → popover |
| Stuck zones | Soft pulsing rings, radius ∝ total seconds stuck; animate only while visible | click → popover |
| Quit points | Muted red door icon | click → sessions that quit here |
| Paths (replay) | Thin ghost trails fading over 3 s, dot per player head, one categorical colour per session | scrubber, play/pause, 1×/4×/16× |
| Feedback pins | Speech-bubble pin | click → text + screenshot |

### 7.2 Dock (bottom panel)

- Uses editor theme (`EditorInterface.get_editor_theme()`), editor fonts and icons — must look built-in.
- Tabs: **Sessions** (list: build, date, duration, deaths, outcome; filters: level, build, date range, outcome), **Layers** (toggles, sliders), **Insights**, **Setup** (wizard + Setup health card), **Server** (URL, read key, Fetch button).
- Insights for the open level, each clickable to focus the editor camera: top 3 death hotspots (e.g. "41 % of players died here 3+ times"), largest stuck zone, most common quit point, never-visited areas.
- Hotspot popover: count, share of sessions, average time spent, "Replay these sessions".
- "Save PNG" exports the current overlay.

### 7.3 Visual rules

- Default overlay opacity 65 %; no layer fully opaque; level must stay readable.
- Markers have outlines to read on light and dark tiles.
- Heatmap never shows grid cells at 100–400 % zoom (linear filtering, enough resolution).
- Editor holds 60 fps with all layers on for 500 sessions × 10 min.

---

## 8. Performance budgets

| What | Budget |
| --- | --- |
| Recorder overhead in game | < 0.1 ms/frame average |
| Session file size | < 200 KB per 10 min uncompressed, < 40 KB gzipped |
| Heatmap compute | < 1 s for 1,000 sessions × 10 min, off main thread |
| Editor fps, all layers | 60 fps for 500 sessions |
| Path replay | 50 sessions at once at 60 fps |
| Server ingest | 50 uploads/s on 1 vCPU / 1 GB |

## 9. Privacy

- No personal data: random UUID session ids, no IPs stored, no device ids, no names.
- Recording off by default in release exports.
- Optional consent prompt helper (`runtime/consent.gd`) for public builds; README explains when it's needed (e.g. GDPR).
- Session files are plain text so testers can see exactly what was recorded.

---

## 10. Workstreams and agent setup (2–3 agents, started by the main agent)

The work is split into five workstreams (below), but **only 2–3 agents work on them**: the main agent plus at most 2 sub-agents that the main agent starts itself. Workstreams are grouped into bundles, one bundle per agent:

| Agent | Bundle | Workstreams | Why together |
| --- | --- | --- | --- |
| Main agent (lead) | Lead bundle | Phase 0, WS-A (runtime recorder), WS-B (shared + tools), all reviews and merges | Runtime and shared code define the data everything else uses; the lead keeps them consistent |
| Sub-agent 1 | Editor bundle | WS-C (editor plugin) | Largest, most visual part; works from `tests/fixtures/` until the reader and generator land |
| Sub-agent 2 (optional) | Server bundle | WS-D (server) + WS-E (CI, demo, e2e, docs) | Fully separate tech (C#); only shares the HTTP contract |

With only 2 agents in total, the main agent also takes the Server bundle.

When to start sub-agents:
1. After M0 is merged and contracts are frozen: start Sub-agent 1 (Editor bundle) and, if you use it, Sub-agent 2 (Server bundle).
2. While they work, the main agent does M1 and M2 (WS-A, WS-B).
3. When a sub-agent reports back, review, run CI, merge, then give it its next milestone or end it.
4. M6 and M8 integration (uploader ↔ server ↔ editor fetch, e2e, release) are led by the main agent.

Each workstream owns specific directories (section 4.1); agents must not edit directories outside their bundle except via a contract change (section 0).

| WS | Name | Owns | Milestones | Depends on |
| --- | --- | --- | --- | --- |
| WS-A | Runtime recorder | `addons/playtrace/runtime/`, `tests/runtime/` | M1, M6 (uploader), M7 (feedback panel, runtime side) | contracts 6.1, 6.3, 6.4 (use a mock HTTP server in tests) |
| WS-B | Shared + tools | `addons/playtrace/shared/`, `tools/`, `tests/shared/` | M2 | contracts 6.2, 6.3, 6.5 |
| WS-C | Editor plugin | `addons/playtrace/plugin.gd`, `addons/playtrace/editor/`, `tests/editor/`, `tests/golden/` | M3, M4, M5, M7 (pins), M1 wizard/setup health UI | WS-B reader + generator (until ready, use `tests/fixtures/`) |
| WS-D | Server | `server/` | M6 (server side) | contract 6.4 |
| WS-E | CI, demo, e2e, docs | `.github/`, `demo/`, `e2e/`, `docs/` (not CONTRACTS.md), `README.md` | M0 (CI part), M6 e2e, M8 | everything for e2e and release |

Merge rules:
- Each sub-agent works on its own branch (`editor/...`, `server/...`). Only the main agent merges to `main`, and only with green CI.
- Rebase on `main` before merging; never force-push `main`.
- If a sub-agent needs a file outside its bundle, it does not edit it: it reports the need to the main agent, who makes the change or updates the contract.

---

## 11. Phases and milestones

### Phase 0 — Foundation (ONE agent, before anything parallel)

**M0 — Repository, CI, frozen contracts**
- [ ] Repo layout from 4.1 created, MIT licence, README stub, `.godot-version` pinned.
- [ ] GitHub Actions: `gdlint`, `gdformat --check`, GdUnit4 headless, `dotnet test`, on every push and PR.
- [ ] `docs/CONTRACTS.md` = section 6 verbatim, plus section 5 (session format) and versioning/compatibility rules (D-002); `docs/openapi.yaml` for 6.4.
- [ ] Stub files with the exact signatures from 6.1, 6.2, 6.3 (bodies `pass` / TODO) so other workstreams compile.
- [ ] `tests/fixtures/`: 5 hand-written valid session files (one per scenario: completed, quit, many deaths, stuck, with feedback) + 1 corrupt file (D-004).
- [ ] ASP.NET Core project skeleton with `/health` and a passing placeholder test.
- [ ] One placeholder test per suite passes in CI (T01).

### Phase 1 — Parallel

**M1 — Recorder, plug-and-play + manual (WS-A; wizard/setup-health UI by WS-C)**
- [ ] Enabling the plugin registers the autoload; disabling removes it.
- [ ] All event types in section 5 recorded to `user://playtrace/sessions/`.
- [ ] Auto player, levels, deaths, stuck, quit per section 2.1; manual API per 6.1; takeover rule per 2.2.
- [ ] Detection report in header and output log; `get_detection_report()` returns warnings per 2.3.
- [ ] Flush every 5 s; crash loses ≤ 5 s.
- [ ] Overhead < 0.1 ms/frame (benchmark).
- [ ] Release exports off by default.
- [ ] Setup wizard and Setup health card in the dock (WS-C).

**M2 — Shared reader, settings, generator, sandbox (WS-B; sandbox scene by WS-E)**
- [ ] Reader per 6.2, robust to corrupt/unknown data.
- [ ] Settings constants + registration of defaults per 6.3.
- [ ] Generator per 6.5 with all five planted features; deterministic.
- [ ] `demo/sandbox.tscn`: small 2D level with a `CharacterBody2D` player in group `player`, spikes, a dead end, a hidden area (the real test game gets its own spec later).

**M3 — 2D heatmap overlay (WS-C) — first public GIF**
- [ ] Density + death layers over the 2D viewport, exact under pan/zoom.
- [ ] Computed on `WorkerThreadPool`; editor never freezes (1,000 sessions).
- [ ] Opacity, palette, kernel radius adjustable.
- [ ] Overlay only for sessions whose level matches the edited scene.
- [ ] All planted features from M2 visible and correct.

**M4 — Dock, stuck zones, quits, insights (WS-C)**
- [ ] Dock per 7.2, editor theme, settings persisted in `res://.playtrace/settings.cfg`.
- [ ] Stuck rings, quit icons, marker clustering with badges.
- [ ] Insights list; click focuses camera. Hotspot popover.
- [ ] Save PNG.

**M5 — Path replay (WS-C)**
- [ ] Ghost trails, scrubber, play/pause, 1×/4×/16×.
- [ ] 50 sessions at 60 fps.
- [ ] "Replay sessions from this hotspot".

**M6 — Remote collection (WS-D server, WS-A uploader, WS-C fetch UI, WS-E e2e)**
- [ ] Server per 6.4, Postgres, `docker compose up` works from a clean machine.
- [ ] Uploader: background upload of finished sessions, retries with exponential backoff (max 1 h), keeps local copy until `201`/`200`.
- [ ] Web builds upload (CORS) and use `fetch` with `keepalive` best effort on tab hide (D-017).
- [ ] Editor Fetch downloads new sessions into `user://playtrace/remote/<project>/`; dock shows local + remote identically.
- [ ] Limits: 2 MB, rate limit, schema validation.
- [ ] Playwright e2e passes (T35) (D-001).

**M7 — In-game feedback (WS-A runtime, WS-C pins)**
- [ ] F8 panel (configurable), pauses game, text + screenshot, writes `feedback` event.
- [ ] Pins on the level with text + screenshot popover.
- [ ] Screenshots upload with the session (JPEG, ≤ 1280 px).

### Phase 2 — Release

**M8 — v0.1 (WS-E, all review)**
- [ ] Godot Asset Library submission + GitHub Release.
- [ ] README: GIF at top, 5-minute quick start (plug-and-play), manual mode section, API reference, self-hosting guide link.
- [ ] `docs/RECIPES.md` with the four recipes from 2.3.
- [ ] Demo project with pre-recorded sessions.
- [ ] Fresh-install script check (T37) + one timed human test (< 5 min to first heatmap) (D-001).
- [ ] CHANGELOG, semver tags, issue templates.
- [ ] All documentation in section 15 complete, reviewed by the main agent, and checked against the final code.

---

## 12. Automated tests

Ground-truth principle: the seeded generator plants known problems; tests assert the tool finds them.

| ID | M | Suite | Test | Passes when |
| --- | --- | --- | --- | --- |
| T01 | M0 | all | Pipeline smoke | lint + GdUnit4 + xUnit placeholders pass in CI |
| T02 | M1 | GdUnit4 | Serialisation round-trip | every event type written then read is identical |
| T03 | M1 | GdUnit4 | Position sampling | 10 s scripted movement → 50 ± 1 `pos`; none when moving < 2 px |
| T04 | M1 | GdUnit4 | Stuck detection | 8 s still → exactly 1 `stuck`; jitter < 16 px counts; paused time doesn't |
| T05 | M1 | GdUnit4 | Quit + crash safety | close → `quit`; killed writer → valid file missing ≤ 5 s |
| T06 | M1 | GdUnit4 | Overhead benchmark | < 0.1 ms/frame avg over 10,000 frames |
| T07 | M1 | GdUnit4 | Disabled mode | no files created; API calls are no-ops |
| T08 | M1 | GdUnit4 | Zero-code plug-and-play | scene with `CharacterBody2D` player, no code; player freed → `death` recorded; detection report says `node_removal` |
| T09 | M1 | GdUnit4 | Auto player resolution | group `player` wins over first `CharacterBody2D`; none found → warning, no crash |
| T10 | M1 | GdUnit4 | Auto death by scene reload | same scene reloaded within 1 s while player alive → one `death` |
| T11 | M1 | GdUnit4 | Manual mode | `mode = manual` → no auto events; explicit calls recorded |
| T12 | M1 | GdUnit4 | Takeover / no double count | mixed auto + `death()` calls → each death counted once |
| T13 | M1 | GdUnit4 | Manual vs auto parity | demo scripted run in manual and auto modes → same death/stuck/quit positions ± 4 px |
| T14 | M2 | GdUnit4 | Generator determinism | same seed → byte-identical files |
| T15 | M2 | GdUnit4 | Reader robustness | corrupt lines, unknown types/fields skipped with warnings |
| T16 | M3 | GdUnit4 | Density grid correctness | single point → peak in right cell; total mass = event count ± 0.1 % |
| T17 | M3 | GdUnit4 | Planted hotspot detection | top death hotspot within 32 px of planted cluster, seeds 1–20 |
| T18 | M3 | GdUnit4 | Unvisited area | planted empty area < 1 % of max density |
| T19 | M3 | GdUnit4 | Golden heatmap image | fixed seed heatmap PNG matches golden within 1 % pixel diff |
| T20 | M3 | GdUnit4 | Viewport transform | world→overlay correct at zoom 0.25/1/4 and after pan |
| T21 | M3 | GdUnit4 | Large data perf | 1,000 × 10 min computed off main thread < 1 s on CI |
| T22 | M4 | GdUnit4 | Filters | each filter returns exactly expected fixture sessions |
| T23 | M4 | GdUnit4 | Insights ranking | fixed seed → expected top-3 hotspots, stuck zone, quit point |
| T24 | M4 | GdUnit4 | Clustering | merged badge count = sum of merged markers |
| T25 | M4 | GdUnit4 | Settings persistence | reload plugin → layer settings restored |
| T26 | M4 | GdUnit4 | Setup health warnings | fixtures trigger each warning in 2.3 exactly once |
| T27 | M5 | GdUnit4 | Replay interpolation | head position = linear interpolation between `pos` events |
| T28 | M5 | GdUnit4 | Hotspot replay filter | only sessions passing through hotspot selected |
| T29 | M6 | xUnit | Ingest happy path | valid gzip upload → 201, events stored (Testcontainers) |
| T30 | M6 | xUnit | Ingest validation | bad schema / > 2 MB / bad key → 400 / 413 / 401, nothing stored |
| T31 | M6 | xUnit | Key separation | ingest key can't read; read key can't write |
| T32 | M6 | xUnit | Rate limiting | over limit → 429 |
| T33 | M6 | xUnit | Idempotent upload | same session twice → 200, no duplicate events |
| T34 | M6 | GdUnit4 | Upload retry | mock server failing → kept locally, retried, succeeds later |
| T35 | M6 | Playwright | Web e2e | exported web demo in headless Chromium → session visible via read API |
| T36 | M7 | GdUnit4 | Feedback event | panel submit → `feedback` with text, position, screenshot file |
| T37 | M8 | script | Fresh install | clean project + plugin + demo sessions → enables with no errors in output log |

Manual checks at each milestone (not automated): overlay appearance on real levels, GIF quality, 5-minute setup timed with one real person.

---

## 13. Coding conventions

- GDScript: static typing on all variables, params and returns; `class_name` for shared types; files `snake_case.gd`; no global state outside the autoload.
- Every public function has a one-line doc comment (`##`).
- Runtime code must be allocation-light in `_process` / `_physics_process` (reuse arrays; no string formatting per frame except when writing an event).
- Log prefix: `Playtrace:`. Warnings via `push_warning`, never `push_error` for recoverable issues.
- C#: nullable enabled, warnings as errors, minimal APIs grouped by feature, EF Core migrations committed.
- Every PR adds or updates tests for the behaviour it changes.

## 14. Open questions (do not block on these; note decisions in DECISIONS.md)

- Final name: verify "Playtrace" is free on the Asset Library, GitHub and itch.io before M8.
- Public demo server, or self-hosting only?
- TileMap levels split across several scenes: one heatmap per scene or per level id?
- Game-defined zones (e.g. "boss arena") with their own stats: v0.1 or v0.2?
- The test game (small 2D platformer with planted problems) gets its own spec.

---

## 15. Documentation requirement (mandatory, part of the definition of done)

The project must ship with well-written, detailed documentation that explains how Playtrace works, how the codebase is organised, and how to use, extend and maintain it. A person who has never seen the project — a user, a new contributor, or a recruiter reading the repo — must be able to understand it from the docs alone.

Documentation is written **alongside the code, not at the end**: each milestone updates the docs it touches, and a milestone is not done while its docs are missing or out of date. The main agent reviews docs together with code before merging.

### 15.1 Required documents

| File | Audience | Must contain |
| --- | --- | --- |
| `README.md` | Everyone | What Playtrace is, GIF/screenshots, features, 5-minute quick start (plug-and-play), link to every doc below, licence |
| `docs/USER_GUIDE.md` | Game developers | Installing; plug-and-play vs manual mode; every overlay layer and dock tab with screenshots; reading insights; path replay; in-game feedback; troubleshooting and FAQ |
| `docs/MANUAL_INTEGRATION.md` | Game developers | Full public API (section 6.1) with an example for every call; all project settings (6.3) with defaults and effects; the takeover rule; Setup health warnings and how to fix each |
| `docs/RECIPES.md` | Game developers | Step-by-step recipes: respawn at checkpoint, co-op, vehicles, one big world split into areas |
| `docs/HOW_IT_WORKS.md` | Curious users, contributors | Plain-language explanation of the whole pipeline: recording → files → upload → reading → heatmap → overlay; how auto-detection guesses player, levels and deaths; how stuck detection and hotspots are computed (with the Gaussian density formula); performance design choices |
| `docs/ARCHITECTURE.md` | Contributors | Components and their responsibilities, the architecture diagram, data flow, threading model (WorkerThreadPool), runtime vs editor vs shared boundary and why, key design decisions with links to DECISIONS.md |
| `docs/CODEBASE.md` | Contributors | Directory-by-directory and file-by-file tour: what each file does, its main classes/functions, and how files depend on each other; where to start reading; how to add a new event type or a new overlay layer (step by step) |
| `docs/CONTRACTS.md` + `docs/openapi.yaml` | Contributors, integrators | Session file format (schema v1) with every field, GDScript API, settings keys, server HTTP API, versioning and compatibility rules |
| `docs/SELF_HOSTING.md` | Developers running the server | Requirements, `docker compose` setup, creating projects and keys, environment variables, HTTPS, backups, upgrading, resource usage |
| `docs/SERVER.md` | Contributors | Server code structure, endpoints → handlers, database schema and migrations, auth, rate limiting, how to run and test locally |
| `docs/TESTING.md` | Contributors | How to run every test suite locally and in CI, what each test ID (section 12) checks, how the generator's planted features work as ground truth, how to update golden images |
| `docs/CONTRIBUTING.md` | Contributors | Dev environment setup, coding conventions (section 13), branch/PR rules, how to propose a contract change |
| `docs/DECISIONS.md` | Contributors | Dated log of design decisions and their reasons |
| `CHANGELOG.md` | Everyone | Changes per version (Keep a Changelog format) |

### 15.2 In-code documentation

- Every GDScript class has a `##` class doc comment explaining its purpose and how it fits into the system; every public function, signal and exported/setting variable has a `##` doc comment. Godot shows these in its built-in help, so they are part of the user-facing docs.
- Every C# public type and method has XML doc comments; the server builds with documentation warnings enabled.
- Non-obvious algorithms (death auto-detection, stuck detection, density grid, marker clustering, replay interpolation) have a short comment block explaining the approach and why it was chosen.
- No commented-out code; TODOs reference an issue or a DECISIONS.md entry.

### 15.3 Quality bar

- Written in clear, plain English; short sections; examples for everything a reader might copy.
- Screenshots and GIFs for every visual feature, stored in `docs/images/`, regenerated when the UI changes.
- Diagrams (architecture, data flow, auto-detection flow) as Mermaid in the Markdown so they stay editable.
- Every code snippet in the docs is real and works with the current version; snippets in USER_GUIDE and MANUAL_INTEGRATION are covered by a doc-snippet check in CI (extract snippets, run them against the demo project headless).
- All internal links work (link checker in CI).
- Docs are updated in the same PR as the code they describe.

---

## 16. Resolved decisions (Phase 0, approved by owner 2026-11-27)

These override anything above that disagrees. The same entries are in `docs/DECISIONS.md` with IDs.

| ID | Decision |
| --- | --- |
| D-001 | Test IDs: M6 Playwright e2e is **T35** (not T28); M8 fresh install is **T37** (not T30). Section 12 is the source of truth for IDs. |
| D-002 | `docs/CONTRACTS.md` = section 6 verbatim + section 5 (session format) + versioning/compatibility rules. |
| D-003 | `PlaytraceSession` lives in `addons/playtrace/shared/session.gd` (`class_name PlaytraceSession`). |
| D-004 | The 5 M0 fixtures are scenarios (completed, quit, many deaths, stuck, with feedback), not values of `outcome()`. |
| D-005 | The repo root is the Godot project (`project.godot` at root); the demo and tests run from it. |
| D-006 | `runtime/playtrace.gd` has no `class_name` (Godot rejects a class name equal to an autoload name). |
| D-007 | `Playtrace.death()` with an empty cause writes `data.cause = "manual"`; auto deaths write `"auto"`. |
| D-008 | CI tests only Godot 4.7.2 (`.godot-version`). Supporting/testing 4.4–4.6 is decided later. |
| D-009 | GdUnit4 v6.2.3 is vendored in `addons/gdUnit4` and excluded from gdlint/gdformat; local and CI use the same copy. |
| D-010 | The doc-snippet CI check (15.3) is added when USER_GUIDE / MANUAL_INTEGRATION exist; the link checker runs from M0. |
| D-011 | No Docker locally: Docker-dependent work (image build, Testcontainers) runs in GitHub Actions. |
| D-012 | The GitHub repo `droidek314/playtrace` is public, permanently. |
| D-013 | `GET /v1/sessions` items use `levels: string[]`; `limit` default 100, max 500 (out-of-range values are clamped). See `docs/openapi.yaml`. (`next` rule replaced by D-016.) |
| D-014 | Doc ownership in Phase 1: editor agent owns `docs/HOW_IT_WORKS.md` (heatmap/overlay parts) and `docs/ARCHITECTURE.md` (editor parts); server agent owns `docs/SERVER.md`, `docs/SELF_HOSTING.md`; the lead owns the rest of `docs/`. |
| D-015 | `demo/sandbox.tscn` is built by the lead together with the generator (moved from WS-E), so planted positions match the level. |
| D-016 | `GET /v1/sessions` `next` is never null: the cursor after the last returned item, or the request's `since` (or `"0"`) when the page is empty. Clients page until `items` is empty and store the last `next` for the next Fetch. |
| D-017 | Web tab-hide upload uses `fetch` with `keepalive: true` instead of `navigator.sendBeacon`, which cannot set `Authorization` / `Content-Encoding`. No HTTP contract change. |
| D-018 | `outcome` everywhere (reader, server, editor) = whichever of `level_complete` / `quit` came last; `unknown` if neither. `duration_ms` = largest `t`. |
| D-019 | Screenshot upload (M7) has no endpoint in 6.4 yet; a contract addition (e.g. `PUT /v1/sessions/{id}/screenshots/{n}.jpg`) is designed at the start of M7. |
| D-020 | Server: keys are `pt_ingest_` / `pt_read_` + 32 random bytes (Base64url), stored as SHA-256 only; session ids unique per project; non-object event lines skipped, only a bad header gives 400; decompressed size capped at 16 MB (413); events stored as one `jsonb` array per session, so downloads have the same content but may differ in key order/spacing; migrations run on start. Details in `docs/SERVER.md`. |
| D-027 | The overlay uses `set_force_draw_over_forwarding_enabled()` + `_forward_canvas_force_draw_over_viewport()`. The plain `_forward_canvas_draw_over_viewport()` only runs while the plugin handles the selected node, so the overlay would vanish when a normal node is selected. |
| D-028 | `docs/` has a `.gdignore` so Godot doesn't import the doc images (the repo root is a Godot project). |
