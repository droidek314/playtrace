# Testing

Playtrace has three kinds of automated tests:

| Suite | Tool | Where | Runs in CI job |
| --- | --- | --- | --- |
| GDScript (plugin, tools, demo) | [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) v6.2.3, headless | `tests/runtime/`, `tests/shared/`, `tests/editor/` | `gdunit` |
| Server | xUnit + `WebApplicationFactory` (+ Testcontainers from M6) | `server/tests/` | `server` |
| End-to-end (from M6) | Playwright | `e2e/` | — |

CI also runs `gdlint` and `gdformat --check`, builds the server Docker image, and checks every Markdown link offline.

## Running the GDScript tests locally

You need Godot 4.7.2 (the version in [`.godot-version`](../.godot-version)). Point `G` at your Godot binary, then from the repo root:

```bash
G="/path/to/godot"
"$G" --headless --path . --import      # once, and after adding a script with class_name
bash addons/gdUnit4/runtest.sh --godot_binary "$G" --headless --ignoreHeadlessMode -a res://tests
```

`--ignoreHeadlessMode` is needed because GdUnit4 refuses headless runs by default (UI input events don't work headless; none of our tests use them). On Windows, use Git Bash for `runtest.sh`. Reports go to `reports/` (git-ignored); CI uploads them as the `gdunit-reports` artifact.

You can also run tests from the Godot editor through the GdUnit4 panel (the plugin is enabled in `project.godot`).

## Lint and format

```bash
pip install gdtoolkit==4.5.0
gdlint addons/playtrace tools tests demo
gdformat --check --line-length 120 addons/playtrace tools tests demo
```

Drop `--check` to reformat. The vendored `addons/gdUnit4/` is never linted (D-009).

## Server tests

```bash
cd server
dotnet test
```

Tests that use Testcontainers need Docker. Without Docker locally, run them in CI by pushing a branch.

## Ground truth: the session generator

Spatial features are tested against data with problems planted at known positions, never against hand-picked numbers.

- [`tools/planted.json`](../tools/planted.json) is the ground truth. It sets the positions in the sandbox level ([`demo/sandbox.tscn`](../demo/sandbox.tscn)) of: `death_cluster` (spikes), `stuck_zone` (end of the dead-end branch), `quit_point` (the hard step), `unvisited_area` (the sealed hidden room) and `backtrack_loop` (the walk into the dead end and back).
- [`tools/session_generator.gd`](../tools/session_generator.gd) (`PlaytraceSessionGenerator`) writes sessions that walk the level and, driven by a seeded RNG, die at the spikes, wander into the dead end, get stuck there, or quit at the hard step. Nobody enters the hidden room.
- The same seed always gives byte-identical files: no clock, no engine version and a fixed key order go into the output.

Generate sessions from the command line:

```bash
"$G" --headless --path . --script tools/generate_sessions.gd -- --seed 1 --count 200 --level res://demo/sandbox.tscn --out user://playtrace/sessions
```

If you move something in the sandbox level, update `planted.json` to match. The generator tests will tell you if the data no longer fits.

## Fixtures

[`tests/fixtures/`](../tests/fixtures/README.md) holds six hand-written session files (five scenarios and one corrupt file), frozen in Phase 0. Changing them is a contract change (see [CONTRACTS.md](CONTRACTS.md)).

## Golden images

T19 compares the seed-1 heatmap with [`tests/golden/heatmap_seed1_magma.png`](../tests/golden/heatmap_seed1_magma.png). It allows under 1 % differing pixels, with a ±3/255 per-channel tolerance. If you change the heatmap on purpose, regenerate the image and check it by eye before committing:

```bash
PLAYTRACE_UPDATE_GOLDEN=1 bash addons/gdUnit4/runtest.sh --godot_binary "$G" --headless --ignoreHeadlessMode -a res://tests/editor
```

The doc screenshots `docs/images/m3_*.png` come from `tests/golden/render_m3_overlay.gd`. It needs a GPU, so run it without `--headless`: `"$G" --path . --script res://tests/golden/render_m3_overlay.gd`.

## Test IDs

Section 12 of [PLAYTRACE_SPEC.md](../PLAYTRACE_SPEC.md) defines the test IDs (T01–T37). Where each one lives:

| ID | What it checks | Test file |
| --- | --- | --- |
| T01 | Pipeline smoke: lint, GdUnit4, xUnit | all suites; `tests/*/contract_test.gd`, `server/tests/.../HealthTests.cs` |
| T02 | Every event type round-trips through writer and reader | `tests/runtime/recorder_test.gd` |
| T03 | 10 s of movement → ~50 `pos`; none when moving < 2 px | `tests/runtime/recorder_test.gd` |
| T04 | Stuck: 8 s still → 1 event; jitter counts; paused time doesn't | `tests/runtime/recorder_test.gd` |
| T05 | Quit on close; a crash loses at most 5 s | `tests/runtime/recorder_test.gd` |
| T06 | Recorder overhead < 0.1 ms/frame over 10,000 frames (prints the measured value) | `tests/runtime/recorder_test.gd` |
| T07 | Recording off → no files, API calls do nothing | `tests/runtime/recorder_test.gd` |
| T08 | Zero-code: freeing a `CharacterBody2D` player records a death | `tests/runtime/recorder_test.gd` |
| T09 | Group `player` wins; no player → warning, no crash | `tests/runtime/recorder_test.gd` |
| T10 | Same-scene reload within 1 s → one death; other scene or later → none | `tests/runtime/recorder_test.gd` |
| T11 | Manual mode records only explicit calls | `tests/runtime/recorder_test.gd` |
| T12 | Takeover: mixing auto and `death()` never double counts | `tests/runtime/recorder_test.gd` |
| T13 | Same scripted run in auto and manual mode → same death/stuck/quit positions ± 4 px | `tests/runtime/recorder_test.gd` |
| T14 | Generator determinism | `tests/shared/generator_test.gd` |
| T15 | Reader robustness | `tests/shared/session_reader_test.gd` |
| T16 | Density grid: peak in the right cell, total mass = event count | `tests/editor/density_grid_test.gd` |
| T17 | Top death hotspot within 32 px of the planted cluster, seeds 1–20 | `tests/editor/planted_test.gd` |
| T18 | Planted unvisited area < 1 % of max density | `tests/editor/planted_test.gd` |
| T19 | Golden heatmap image | `tests/editor/planted_test.gd` |
| T20 | World → overlay transform at zoom 0.25/1/4 and after pan | `tests/editor/overlay_transform_test.gd` |
| T21 | 1,000 × 10 min computed off the main thread in < 1 s | `tests/editor/heatmap_perf_test.gd` |

`tests/shared/generator_test.gd` also checks that every planted feature is present in 200 generated sessions, and `tests/shared/sandbox_test.gd` checks that the sandbox loads and its player stands on the ground. Other IDs are added to this table as their milestones land.

### How the recorder tests work

`tests/runtime/recorder_test.gd` never uses the global autoload (it doesn't record under a test runner; D-030). Each test makes its own recorder instance and calls its internal `_configure()` with hooks for the clock, the current scene and the paused state. It then calls `_step()` once per simulated 16 ms frame. Ten "seconds" of play run in milliseconds, and scene reloads are simulated by freeing the level node and swapping in a new one with the same `scene_file_path`.
