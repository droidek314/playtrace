# Test fixtures (frozen, Phase 0)

Hand-written session files in schema v1 (see [docs/CONTRACTS.md](../../docs/CONTRACTS.md)). All are for level `res://demo/sandbox.tscn` except `with_feedback.jsonl`, which uses manual level id `level_1`.

| File | Scenario | Expected `outcome()` | Deaths |
| --- | --- | --- | --- |
| `completed.jsonl` | Reaches a checkpoint, completes the level | `completed` | 0 |
| `quit.jsonl` | Wanders, fires one `custom` event, quits | `quit` | 0 |
| `many_deaths.jsonl` | 8 spike deaths clustered at x≈910–918, y=388, plus 1 elsewhere | `quit` | 9 |
| `stuck.jsonl` | Stuck 12.4 s at (1540, 300), then completes | `completed` | 0 |
| `with_feedback.jsonl` | Manual mode, one `feedback` with screenshot, one manual death | `quit` | 1 |
| `corrupt.jsonl` | Valid header; 2 truncated lines, 1 non-JSON line, 1 JSON array line, 1 unknown type, 1 unknown field | `unknown` (final `quit` line is truncated) | 1 |

From `corrupt.jsonl` a reader must keep exactly 4 events (`level_enter`, `pos` at t=200, `pos` at t=1000 with its extra field ignored, `death`), drop the unknown `teleport` type and the 4 bad lines, and record one warning for the file.

Changing these files is a contract change (spec section 0).
