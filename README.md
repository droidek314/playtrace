# Playtrace

> Work in progress. Not usable yet.

Playtrace is a free, open-source Godot 4 plugin that shows where playtesters die, get stuck, get lost and quit, drawn directly over your 2D level inside the Godot editor.

- Plug-and-play: enable the plugin, press Play, see deaths on the level. No code needed.
- Manual mode: explicit `Playtrace.death()`, `Playtrace.level()` and similar calls when you want control.
- Optional self-hosted server to collect sessions from remote testers, including web builds.

## Status

Phase 1. Done: the recorder (M1), the shared reader and session generator (M2), the heatmap overlay (M3), and the collection server (M6, server side). See [PLAYTRACE_SPEC.md](PLAYTRACE_SPEC.md) for the full plan.

## Documentation

- [Manual integration](docs/MANUAL_INTEGRATION.md): the `Playtrace` API, every setting, auto-detection rules, setup warnings
- [Contracts](docs/CONTRACTS.md): session file format, GDScript API, settings, server API
- [Decisions](docs/DECISIONS.md): design decisions and their reasons
- [How it works](docs/HOW_IT_WORKS.md): from recorded events to the heatmap
- [Architecture](docs/ARCHITECTURE.md): components, threading, runtime/editor boundary
- [Testing](docs/TESTING.md): how to run every test suite
- [Codebase tour](docs/CODEBASE.md): what each file does
- [Self-hosting](docs/SELF_HOSTING.md): run the collection server with Docker
- [Server internals](docs/SERVER.md): server code, database and API handlers

## Licence

[MIT](LICENSE)
