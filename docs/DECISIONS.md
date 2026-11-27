# Decisions

Dated log of design decisions. One line each: date, ID, decision, reason. Section 16 of [PLAYTRACE_SPEC.md](../PLAYTRACE_SPEC.md) mirrors the Phase 0 entries.

| Date | ID | Decision | Reason |
| --- | --- | --- | --- |
| 2026-11-27 | D-001 | M6 Playwright e2e is T35; M8 fresh install is T37. | The milestone text cited T28/T30, which are other tests in section 12. |
| 2026-11-27 | D-002 | CONTRACTS.md = spec section 6 verbatim + section 5 + versioning rules. | Section 11 said "section 6 verbatim" but section 15.1 also requires the file format and versioning rules. |
| 2026-11-27 | D-003 | `PlaytraceSession` lives in `shared/session.gd`. | Spec 6.2 names the type but no file. |
| 2026-11-27 | D-004 | The 5 M0 fixtures are scenarios, not `outcome()` values. | `outcome()` has only three values, but five fixtures are listed. |
| 2026-11-27 | D-005 | Repo root is the Godot project. | Headless tests, the generator and the demo need a `project.godot`; the layout in 4.1 had none. |
| 2026-11-27 | D-006 | `runtime/playtrace.gd` has no `class_name`. | Godot rejects a class name equal to an autoload name. |
| 2026-11-27 | D-007 | `death()` with empty cause writes `"manual"`. | Keeps manual deaths distinguishable from `"auto"` ones; an empty string carries no information. |
| 2026-11-27 | D-008 | CI tests only Godot 4.7.2. | One pinned version keeps CI simple; older-version support is decided later. |
| 2026-11-27 | D-009 | GdUnit4 v6.2.3 vendored in `addons/gdUnit4`, excluded from lint. | Same test framework copy locally and in CI; it is third-party code. |
| 2026-11-27 | D-010 | Doc-snippet CI check comes with USER_GUIDE/MANUAL_INTEGRATION; link checker from M0. | Nothing to extract snippets from yet. |
| 2026-11-27 | D-011 | Docker-dependent steps run only in GitHub Actions. | Docker is not installed on the dev machine. |
| 2026-11-27 | D-012 | GitHub repo is public, permanently. | Owner decision; needed for the Asset Library and free CI minutes. |
| 2026-11-27 | D-013 | Session list items use `levels: string[]`; `limit` defaults to 100, max 500; `next` is null when no more items. | Spec 6.4 wrote "level(s)" and gave no limit bounds. |
| 2026-11-27 | D-014 | Doc ownership: editor agent owns `HOW_IT_WORKS.md` (heatmap/overlay parts) and `ARCHITECTURE.md` (editor parts); server agent owns `SERVER.md` and `SELF_HOSTING.md`; the lead owns everything else in `docs/`. | Two agents editing the same doc file would conflict; each writes the docs for the code it builds (spec 15). |
| 2026-11-27 | D-015 | The lead builds `demo/sandbox.tscn` together with the generator (moved from WS-E). | The generator's planted positions must match the sandbox layout exactly; one owner keeps them in sync. |
| 2026-11-27 | D-016 | `GET /v1/sessions` `next` is never null: cursor after the last returned item, or the request's `since` (or `"0"`) when the page is empty. Supersedes the `next` part of D-013. | With a null cursor on the last page, the editor could never fetch "only new" sessions; it would re-scan everything (found by the server agent). |
| 2026-11-27 | D-017 | Web tab-hide upload uses `fetch(..., {keepalive: true})`, not `navigator.sendBeacon`. | `sendBeacon` cannot set `Authorization` or `Content-Encoding`, so it would always get 401/400; keepalive fetch can, with a similar size limit, and needs no contract change. |
| 2026-11-27 | D-018 | `outcome` = whichever of `level_complete` / `quit` came last, else `unknown`, in the reader, server and editor alike; `duration_ms` = largest `t`. | The server first used "any level_complete wins", which would show local and remote copies of a session differently. |
| 2026-11-27 | D-019 | Screenshot upload has no endpoint yet; designed as a contract addition at the start of M7. | Spec 6.4 has no way to send the screenshots M7 requires. |
| 2026-11-27 | D-020 | Server keys: `pt_ingest_` / `pt_read_` + 32 random bytes, stored as SHA-256 only. | 256-bit random keys don't need a slow hash; the prefix makes mix-ups obvious. |
| 2026-11-27 | D-021 | Session ids are unique per project, not globally. | One project must not be able to detect or block another project's ids. |
| 2026-11-27 | D-022 | Server skips non-object event lines and keeps unknown types/fields; only a bad header gives 400. | Same rule as the reader; a crash can truncate the last line and rejecting would lose the whole session. |
| 2026-11-27 | D-023 | Decompressed upload size capped at 16 MB (413). Text PostgreSQL `jsonb` cannot store (`\u0000`, lone surrogates) gives 400. | Guards against gzip bombs; turns a would-be 500 into a clear client error. |
| 2026-11-27 | D-024 | Events stored as one `jsonb` array per session plus summary columns; downloads rebuild JSONL with the same content but possibly different key order/spacing. | One insert per upload, one row per download, and listing never touches events. |
| 2026-11-27 | D-025 | Server tables use snake_case (EFCore.NamingConventions); migrations run on start by default (`Playtrace:MigrateOnStart`). | Easier `psql` queries and backups; `docker compose up` works with no extra step. |
| 2026-11-27 | D-026 | List `limit` outside 1–500 is clamped; a malformed `since` gives 400. | Lenient for a value clients compute; a garbled cursor is a client bug worth surfacing. |
