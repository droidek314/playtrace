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
