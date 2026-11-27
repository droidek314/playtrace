# Playtrace server

The server collects session files from game builds and hands them to the Godot editor. It is a small ASP.NET Core (.NET 10) app with a PostgreSQL database. This page is for contributors. To run your own server, read [SELF_HOSTING.md](SELF_HOSTING.md).

The HTTP contract is in [CONTRACTS.md](CONTRACTS.md) (section 6.4) and [openapi.yaml](openapi.yaml). The server must match it exactly.

## Code structure

```
server/
  Playtrace.slnx                 solution
  Directory.Build.props          nullable, warnings as errors, XML docs required
  global.json                    .NET SDK version
  dotnet-tools.json              local tool: dotnet-ef (migrations)
  Dockerfile, docker-compose.yml
  src/Playtrace.Server/
    Program.cs                   service setup, middleware, create-project CLI, /health
    Data/PlaytraceDb.cs          EF Core context and the Project and Session entities
    Data/Migrations/             EF Core migrations (committed)
    Projects/ProjectKeys.cs      key generation, hashing, bearer-key lookup
    Sessions/SessionEndpoints.cs the /v1/sessions endpoints
    Sessions/SessionParser.cs    JSONL session file -> Session row (validation and summary)
  tests/Playtrace.Server.Tests/
    HealthTests.cs               /health, no database needed
    PostgresFixture.cs           Testcontainers PostgreSQL + WebApplicationFactory host
    IngestTests.cs               T29, T30, T33, list filters and paging, outcome rule
    KeyAndRateLimitTests.cs      T31, T32, CORS
```

Endpoints are minimal APIs grouped by feature: each feature folder has a static class with a `Map...Endpoints` extension method that `Program.cs` calls.

## Endpoints and handlers

| Endpoint | Handler | Auth |
| --- | --- | --- |
| `GET /health` | lambda in `Program.cs` | none |
| `POST /v1/sessions` | `SessionEndpoints.Upload` | ingest key |
| `GET /v1/sessions` | `SessionEndpoints.List` | read key |
| `GET /v1/sessions/{id}` | `SessionEndpoints.Get` | read key |

### Upload (`POST /v1/sessions`)

Checks run in this order, and nothing is written to the database unless all pass:

1. Rate limit (middleware) → `429`.
2. Ingest key → `401` if missing, wrong, or a read key.
3. `Content-Length` over 2 MB, or the body turns out longer than 2 MB → `413`.
4. `Content-Encoding` is not `gzip` → `400`.
5. Body is not valid gzip → `400`. It inflates past 16 MB → `413` (protects against gzip bombs).
6. Line 1 is not a JSON object with `schema` = 1, `type` = `"session_start"` and a UUID `session` → `400`.
7. A session with this id already exists in this project → `200`, nothing changes.
8. Insert → `201`. If a parallel upload of the same session wins the insert, the unique index fails and the handler returns `200`.

Event lines follow the reader rule from the contract: a line that is not a JSON object (for example a truncated last line after a crash) is skipped. Unknown event types and fields are kept as they are.

While parsing, `SessionParser` also computes the list summary:

| Field | How |
| --- | --- |
| `levels` | `level` of each `level_enter`, in order of first entry, no repeats |
| `build`, `started_utc` | copied from the header (`""` if missing) |
| `duration_ms` | the largest `t` of any event |
| `outcome` | whichever of `level_complete` (`completed`) or `quit` (`quit`) came last, else `unknown`; same rule as `PlaytraceSession.outcome()` (D-018) |
| `deaths` | number of `death` events |

### List (`GET /v1/sessions`)

Returns `{ "items": [...], "next": "<cursor>" }`, oldest upload first. Query parameters:

- `since`: cursor from a previous `next`. The cursor is the `seq` of the last item returned (opaque to clients).
- `level`: only sessions whose `levels` contain this id.
- `build`: only sessions with this exact build.
- `limit`: default 100, clamped to 1–500.

`next` is never null (D-016): it is the cursor after the last returned item, or the request's `since` (`"0"` if none) when the page is empty. Clients page until `items` is empty and keep the last `next`, so the next Fetch gets only new sessions.

### Download (`GET /v1/sessions/{id}`)

Rebuilds the JSONL file from the stored header and events, gzips it, and returns it with `Content-Encoding: gzip`. Another project's session, or an unknown id, gives `404`. Key order and number spacing inside a line may differ from the uploaded file (PostgreSQL `jsonb` normalises them); the content is the same.

## Database schema

Tables and columns use snake_case (EFCore.NamingConventions).

`projects`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint identity | primary key |
| `name` | text | from `create-project` |
| `ingest_key_hash` | bytea | SHA-256 of the ingest key, unique |
| `read_key_hash` | bytea | SHA-256 of the read key, unique |

`sessions`

| Column | Type | Notes |
| --- | --- | --- |
| `seq` | bigint identity | primary key, upload order, list cursor |
| `project_id` | bigint | foreign key to `projects`, cascade delete |
| `session_id` | uuid | from the header; unique together with `project_id` |
| `build`, `started_utc`, `outcome` | text | summary |
| `levels` | text[] | summary |
| `duration_ms` | bigint | summary |
| `deaths` | integer | summary |
| `header` | jsonb | the header line |
| `events` | jsonb | array of all event objects, in file order |

Indexes: unique `(project_id, session_id)` for idempotency, `(project_id, seq)` for paging.

Storing the events as one `jsonb` array per session keeps uploads to a single insert and downloads to a single row read. The summary columns mean the list never has to open the events.

### Migrations

Migrations live in `src/Playtrace.Server/Data/Migrations/` and are committed. The server applies them on start (`Playtrace:MigrateOnStart`, default `true`). CI fails if the model has changes without a migration.

To add a migration after changing an entity in `PlaytraceDb.cs`:

```sh
cd server
dotnet tool restore
ConnectionStrings__Playtrace="Host=localhost" dotnet ef migrations add <Name> --project src/Playtrace.Server --output-dir Data/Migrations
```

The connection string only has to be set; `migrations add` does not connect.

## Auth

There is no login. Each project has two random keys, created by the CLI:

```sh
dotnet Playtrace.Server.dll create-project my-game
```

- Ingest key `pt_ingest_...`: goes into game builds. It can only upload.
- Read key `pt_read_...`: goes into the editor. It can only list and download.

Each key is 32 random bytes from `RandomNumberGenerator`, Base64url encoded. The database stores only the SHA-256 of each key. A fast hash is safe here because the keys are random and long; a slow password hash would only make every request slower. The handlers look up the project by the hash of the `Authorization: Bearer` token (`ProjectKeys.FindByIngestKeyAsync` / `FindByReadKeyAsync`). A key of the wrong kind is simply not found, so it gets `401`.

## CORS

Only `POST /v1/sessions` has a CORS policy: any origin, method `POST`, headers `Authorization`, `Content-Type`, `Content-Encoding`. This lets web builds upload from any host (for example itch.io). The `GET` endpoints have no CORS policy, so browsers on other origins cannot read the answers.

## Rate limiting

ASP.NET Core's built-in rate limiter, fixed window of one minute, applied to the upload endpoint only. The partition key is the SHA-256 of the `Authorization` header, so each ingest key has its own budget. The limit is `Playtrace:UploadsPerMinute` (default 60; environment variable `Playtrace__UploadsPerMinute`). Over the limit the server answers `429`.

Client IP addresses are not used for rate limiting, and are never stored or logged. Request logging is off (`Microsoft.AspNetCore` logs only warnings).

## Configuration

| Key | Environment variable | Default |
| --- | --- | --- |
| `ConnectionStrings:Playtrace` | `ConnectionStrings__Playtrace` | none (required) |
| `Playtrace:UploadsPerMinute` | `Playtrace__UploadsPerMinute` | `60` |
| `Playtrace:MigrateOnStart` | `Playtrace__MigrateOnStart` | `true` |

## Run locally

You need the .NET 10 SDK and a PostgreSQL server (any 13+).

```sh
cd server
export ConnectionStrings__Playtrace="Host=localhost;Database=playtrace;Username=postgres;Password=postgres"
dotnet run --project src/Playtrace.Server -- create-project dev
dotnet run --project src/Playtrace.Server
```

Upload a fixture and list it:

```sh
gzip -c ../tests/fixtures/completed.jsonl > /tmp/s.gz
curl -i -X POST http://localhost:5191/v1/sessions -H "Authorization: Bearer <ingest key>" \
  -H "Content-Encoding: gzip" -H "Content-Type: application/x-ndjson" --data-binary @/tmp/s.gz
curl http://localhost:5191/v1/sessions -H "Authorization: Bearer <read key>"
```

The port comes from `src/Playtrace.Server/Properties/launchSettings.json`; the Docker image listens on 8080.

## Tests

```sh
cd server
dotnet test
```

The database tests (T29–T33) start a `postgres:17` container with Testcontainers, so they need Docker. All of them share one container and run one after another (xUnit collection `db`); each test creates its own project, so tests never see each other's data. The upload payloads are the frozen fixtures from `tests/fixtures/`.

Without Docker, run only the tests that need no database:

```sh
dotnet test --filter "FullyQualifiedName~HealthTests"
```

In CI (`.github/workflows/ci.yml`):

- job `server`: checks for missing migrations, then runs every test.
- job `docker-build`: builds the image, runs `docker compose up`, creates a project with the CLI, uploads a fixture with curl and lists it.

| Test | What it checks |
| --- | --- |
| T29 | Valid gzip upload → `201`; list summary is right; download matches the upload line by line; corrupt lines skipped |
| T30 | Bad schema, header, gzip or `Content-Encoding` → `400`; over 2 MB or a gzip bomb → `413`; no or wrong key → `401`; nothing stored |
| T31 | Ingest key cannot list or download; read key cannot upload; another project's read key cannot see the session |
| T32 | With a limit of 3, the 4th upload in a minute → `429`; another key still gets `201` |
| T33 | Same session twice → `201` then `200`; stored once, no duplicate events |
