# Playtrace

> Work in progress. Not usable yet.

Playtrace is a free, open-source Godot 4 plugin that shows where playtesters die, get stuck, get lost and quit, drawn directly over your 2D level inside the Godot editor.

- Plug-and-play: enable the plugin, press Play, see deaths on the level. No code needed.
- Manual mode: explicit `Playtrace.death()`, `Playtrace.level()` and similar calls when you want control.
- Optional self-hosted server to collect sessions from remote testers, including web builds.

## Status

Phase 0 (repository, CI, frozen contracts). See [PLAYTRACE_SPEC.md](PLAYTRACE_SPEC.md) for the full plan.

## Documentation

- [Contracts](docs/CONTRACTS.md): session file format, GDScript API, settings, server API
- [Decisions](docs/DECISIONS.md): design decisions and their reasons

## Licence

[MIT](LICENSE)
