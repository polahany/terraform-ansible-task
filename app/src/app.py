"""A small JSON API whose records live exclusively in PostgreSQL."""

import click
import psycopg
from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from . import db


def create_app():
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 64 * 1024

    @app.cli.command("init-db")
    def init_db():
        """Create the notes table without changing existing records."""
        db.initialize()
        click.echo("Database schema is ready.")

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(error=error.description), error.code

    @app.errorhandler(psycopg.Error)
    def database_error(error):
        # Do not expose connection details or SQL in the response or logs.
        app.logger.warning("Database request failed (%s)", type(error).__name__)
        return jsonify(error="Database temporarily unavailable"), 503

    @app.get("/")
    def index():
        return jsonify(service="notes-api", endpoints=["/notes", "/health", "/live"])

    @app.get("/live")
    def live():
        return jsonify(status="ok")

    @app.get("/health")
    def health():
        with db.connect() as connection:
            # Also check schema availability and read permission.
            connection.execute("SELECT id FROM notes LIMIT 1")
        return jsonify(status="ok", database="ready")

    @app.get("/notes")
    def list_notes():
        try:
            limit = int(request.args.get("limit", "100"))
            offset = int(request.args.get("offset", "0"))
            if not 1 <= limit <= 100 or not 0 <= offset <= 2147483647:
                raise ValueError
        except ValueError:
            return jsonify(error="limit must be 1-100 and offset 0-2147483647"), 400
        with db.connect() as connection:
            rows = connection.execute(
                "SELECT * FROM notes ORDER BY id DESC LIMIT %s OFFSET %s",
                (limit, offset),
            ).fetchall()
        return jsonify(notes=[serialize(row) for row in rows])

    @app.post("/notes")
    def create_note():
        data = request.get_json()
        if not isinstance(data, dict):
            return jsonify(error="Expected a JSON object"), 400
        title, content = data.get("title"), data.get("content", "")
        if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
            return jsonify(error="title must contain 1-200 characters"), 400
        if not isinstance(content, str) or len(content) > 10000:
            return jsonify(error="content must be a string of at most 10000 characters"), 400
        if "\x00" in title or "\x00" in content:
            return jsonify(error="Null characters are not allowed"), 400
        with db.connect() as connection:
            row = connection.execute(
                "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING *",
                (title.strip(), content),
            ).fetchone()
        return jsonify(serialize(row)), 201, {"Location": f"/notes/{row['id']}"}

    @app.get("/notes/<int:note_id>")
    def get_note(note_id):
        with db.connect() as connection:
            row = connection.execute(
                "SELECT * FROM notes WHERE id = %s", (note_id,)
            ).fetchone()
        if row is None:
            return jsonify(error="Note not found"), 404
        return jsonify(serialize(row))

    @app.delete("/notes/<int:note_id>")
    def delete_note(note_id):
        with db.connect() as connection:
            row = connection.execute(
                "DELETE FROM notes WHERE id = %s RETURNING id", (note_id,)
            ).fetchone()
        if row is None:
            return jsonify(error="Note not found"), 404
        return "", 204

    return app


def serialize(row):
    return {**row, "created_at": row["created_at"].isoformat()}
