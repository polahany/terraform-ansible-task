# Notes API

Python Flask + Gunicorn + PostgreSQL. Records are stored only in PostgreSQL.
This is a small unauthenticated lab API: anyone who can reach it can read,
create and delete notes. It is not intended for sensitive data.

## Run locally with Docker Compose

From the repository root:

```powershell
docker compose up --build
```

Compose starts PostgreSQL, waits for it to become healthy, creates the notes
table with a one-time `db-init` container, and then starts the API. Open
`http://127.0.0.1:8000`. Both published ports bind to localhost only.

Create and list a note from another PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/notes -Method Post -ContentType 'application/json' -Body '{"title":"First note","content":"Stored in PostgreSQL"}'
Invoke-RestMethod http://127.0.0.1:8000/notes
```

Stop the stack while preserving records:

```powershell
docker compose down
```

To also delete the local database volume and all notes:

```powershell
docker compose down --volumes
```

The local defaults are `notes`, `notes_app`, and `dev-password`. Override them
by setting `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` in PowerShell
before running Compose. These defaults are for local development only.

## Configuration

Set `DB_HOST`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` in the process environment.
`DB_PORT` defaults to `5432`. `.env.example` documents the settings; the app
does not automatically load `.env` files. Never commit real credentials.
For EC2, `DB_HOST` will be the database instance's private IP.

The database and dedicated user must already exist. The schema command needs
permission to create a table in the database's default schema. It creates the
notes table if absent and preserves existing data. It is not a migration system.

## Local Python development

From `app/`, with a reachable PostgreSQL database and environment configured:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python -m flask --app src.app:create_app init-db
.\.venv\Scripts\python -m flask --app src.app:create_app run --host 127.0.0.1 --port 8000
```

The Flask server is for local development. The Linux container uses Gunicorn.

## Container image

From the repository root:

```sh
docker build -t barq-notes:1.0.0 ./app
```

The image runs as UID/GID 10001 on port 8080. It includes a database-aware
health check. Supply the database environment to the container. Before serving
traffic, run `python -m flask --app src.app:create_app init-db` in a one-off
container with the same database settings. Later deployment automation should
wait for PostgreSQL before running this command and starting the application.
No database is created on app startup, and no records are reset on restart.
Connections are opened per request, so requests can recover when the database
returns. Connection and statement timeouts bound database waits.

The future Nginx container should proxy to `http://app:8080` on a shared local
Docker network. Keep this app port unpublished in the deployment Compose file.

## API

| Method | Path | Result |
| --- | --- | --- |
| GET | `/` | Service information |
| GET | `/live` | Process liveness without querying PostgreSQL |
| GET | `/health` | Database and schema readiness; 503 on database failure |
| POST | `/notes` | Create a note; 201 and Location header |
| GET | `/notes?limit=100&offset=0` | Newest notes first, up to 100 per page |
| GET | `/notes/1` | Retrieve a note, or 404 |
| DELETE | `/notes/1` | Delete a note; 204, or 404 if absent |

Example using the local development server:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/notes -Method Post -ContentType 'application/json' -Body '{"title":"First note","content":"Stored in PostgreSQL"}'
Invoke-RestMethod http://127.0.0.1:8000/notes
```

Titles must contain 1-200 characters after trimming; content defaults to empty
and is limited to 10,000 characters. Request bodies are limited to 64 KiB.
Timestamps use ISO 8601. SQL values use bound parameters.

## Tests

From `app/`, after installing requirements:

```sh
python -m unittest discover -s tests -v
```

Tests use mocked database connections for API validation, parameterized SQL,
response codes and database failures. They do not establish real PostgreSQL
connectivity or prove container operation. Infrastructure, persistence and
backup/restore validation belong to the later deployment stage.

References: [Flask deployment](https://flask.palletsprojects.com/en/stable/deploying/gunicorn/)
and [Psycopg usage](https://www.psycopg.org/psycopg3/docs/basic/usage.html).
