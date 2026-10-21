"""PostgreSQL connections and explicit, repeatable schema initialization."""

import os
from pathlib import Path

import psycopg
from psycopg.rows import dict_row


def connect():
    required = ("DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Missing database settings: " + ", ".join(missing))
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3,
        options="-c statement_timeout=5000",
        row_factory=dict_row,
    )


def initialize():
    with connect() as connection:
        connection.execute(Path(__file__).with_name("schema.sql").read_text())
