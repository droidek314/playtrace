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

Added with M3 (heatmap). This section will explain how to regenerate them.

## Test IDs

Section 12 of [PLAYTRACE_SPEC.md](../PLAYTRACE_SPEC.md) defines the test IDs (T01–T37). Where each one lives:

| ID | What it checks | Test file |
| --- | --- | --- |
| T01 | Pipeline smoke: lint, GdUnit4, xUnit | all suites; `tests/*/contract_test.gd`, `server/tests/.../HealthTests.cs` |
| T14 | Generator determinism | `tests/shared/generator_test.gd` |
| T15 | Reader robustness | `tests/shared/session_reader_test.gd` |

`tests/shared/generator_test.gd` also checks that every planted feature is present in 200 generated sessions, and `tests/shared/sandbox_test.gd` checks that the sandbox loads and its player stands on the ground. Other IDs are added to this table as their milestones land.
