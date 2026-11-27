# Self-hosting the Playtrace server

The server collects sessions from your playtesters' builds (desktop and web) so you can see them in the Godot editor. You only need it for remote testers. When you play from the editor, sessions stay on your machine and no server is needed.

How the server works inside is described in [SERVER.md](SERVER.md).

## Requirements

- A Linux machine or VPS with Docker and the Docker Compose plugin.
- 1 vCPU and 1 GB RAM is enough (see [Resource usage](#resource-usage)).
- A domain name and HTTPS if testers upload over the internet. Web builds served over HTTPS (for example from itch.io) can only upload to an HTTPS server.

## Start the server

```sh
git clone https://github.com/droidek314/playtrace.git
cd playtrace/server
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" > .env
docker compose up -d
```

This starts two containers: `server` (port 8080) and `db` (PostgreSQL 17). The server creates or updates the database tables on start. Check it:

```sh
curl http://localhost:8080/health
# {"status":"ok"}
```

Set `POSTGRES_PASSWORD` before the first start. The database keeps the password it was created with, so changing `.env` later does not change it.

## Create a project and keys

Each game gets its own project with two keys:

```sh
docker compose exec server dotnet Playtrace.Server.dll create-project my-game
```

It prints:

- an **ingest key** (`pt_ingest_...`): put it in the game, in project setting `playtrace/server/ingest_key`, and the server URL in `playtrace/server/url`. It can only upload, so it is fine that it ships inside your builds.
- a **read key** (`pt_read_...`): paste it into the editor's Server tab. It can read every session of the project, so keep it private and out of version control.

Save both keys right away. The server stores only their SHA-256 hashes and cannot show them again. If you lose a key, create a new project.

## Environment variables

Put these in `server/.env`; `docker compose` reads that file.

| Variable | Default | Meaning |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | `playtrace` | Database password. Change it. |
| `PLAYTRACE_UPLOADS_PER_MINUTE` | `60` | Uploads allowed per minute per ingest key. More get `429`, and the game retries later. |

The server itself reads `ConnectionStrings__Playtrace`, `Playtrace__UploadsPerMinute` and `Playtrace__MigrateOnStart` (default `true`). `docker-compose.yml` sets the first two from the variables above.

## HTTPS with a reverse proxy

The server speaks plain HTTP on port 8080. Put a reverse proxy in front of it for HTTPS. With [Caddy](https://caddyserver.com), which gets certificates automatically, the whole `Caddyfile` is:

```
playtrace.example.com {
    reverse_proxy localhost:8080
}
```

With nginx:

```nginx
server {
    listen 443 ssl;
    server_name playtrace.example.com;
    ssl_certificate     /etc/letsencrypt/live/playtrace.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/playtrace.example.com/privkey.pem;
    client_max_body_size 3m;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
```

Then stop port 8080 from being reachable from outside: in `docker-compose.yml` change `"8080:8080"` to `"127.0.0.1:8080:8080"`.

The server never stores or logs client IP addresses. If your proxy writes access logs, those contain IPs; turn them off or shorten their retention if that matters for you (for example under GDPR).

## Backups

All data is in PostgreSQL. Back it up with `pg_dump`:

```sh
docker compose exec -T db pg_dump -U playtrace -Fc playtrace > playtrace-$(date +%F).dump
```

Restore into a fresh install (server stopped, database running):

```sh
docker compose up -d db
docker compose exec -T db pg_restore -U playtrace -d playtrace --clean --if-exists < playtrace-2026-11-27.dump
docker compose up -d
```

The data lives in the Docker volume `server_pgdata`. `docker compose down` keeps it; `docker compose down -v` deletes it.

## Upgrading

```sh
cd playtrace
git pull
cd server
docker compose up -d --build
```

The server applies new database migrations when it starts. Make a backup first. Within `/v1` of the API, older game builds keep working with a newer server.

## Resource usage

- **CPU and memory:** the server is sized to take 50 uploads per second on 1 vCPU and 1 GB RAM, which is far more than a playtest needs. Idle, the two containers use roughly 150–250 MB RAM together.
- **Upload limits:** 2 MB compressed per session, 16 MB after decompression. A 10-minute session is about 200 KB of JSON before compression and under 40 KB gzipped.
- **Disk:** PostgreSQL stores each session as `jsonb` (compressed by PostgreSQL), roughly 50–150 KB per 10-minute session. 10,000 sessions take on the order of 1 GB.

## Troubleshooting

- **`docker compose logs server`** shows startup errors, such as a wrong database password.
- **`401`**: wrong key, or the wrong kind of key (the game needs the ingest key, the editor the read key).
- **`413`**: the session is larger than 2 MB compressed.
- **`429`**: too many uploads for this key in one minute. The game keeps the session and retries.
- **Web build cannot upload:** the server must be HTTPS when the game page is HTTPS.
