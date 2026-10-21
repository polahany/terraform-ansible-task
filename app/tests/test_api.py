import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import psycopg

from src.app import create_app


class NotesApiTests(unittest.TestCase):
    def setUp(self):
        self.client = create_app().test_client()
        self.patcher = patch("src.app.db.connect")
        self.connect = self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.connection = self.connect.return_value.__enter__.return_value
        self.row = dict(id=1, title="Test", content="Body",
                        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc))

    def test_liveness_does_not_need_database(self):
        self.assertEqual(self.client.get("/live").status_code, 200)
        self.connect.assert_not_called()

    def test_create_uses_parameters_and_returns_location(self):
        self.connection.execute.return_value.fetchone.return_value = self.row
        response = self.client.post("/notes", json={"title": "  Test  ", "content": "'; DROP TABLE notes; --"})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.headers["Location"], "/notes/1")
        sql, parameters = self.connection.execute.call_args.args
        self.assertNotIn("DROP TABLE", sql)
        self.assertEqual(parameters, ("Test", "'; DROP TABLE notes; --"))
        self.assertEqual(response.json["created_at"], "2026-01-01T00:00:00+00:00")

    def test_invalid_bodies_do_not_touch_database(self):
        for body in [[], {}, {"title": " "}, {"title": 12},
                     {"title": "x" * 201}, {"title": "x", "content": None},
                     {"title": "x", "content": "x" * 10001}, {"title": "\x00"}]:
            with self.subTest(body_type=type(body)):
                self.assertEqual(self.client.post("/notes", json=body).status_code, 400)
        self.connect.assert_not_called()

    def test_malformed_and_oversized_requests(self):
        self.assertEqual(self.client.post("/notes", data="{", content_type="application/json").status_code, 400)
        self.assertEqual(self.client.post("/notes", data="text").status_code, 415)
        self.assertEqual(self.client.post("/notes", json={"title": "x" * 70000}).status_code, 413)
        self.connect.assert_not_called()

    def test_pagination_and_list(self):
        self.connection.execute.return_value.fetchall.return_value = [self.row]
        response = self.client.get("/notes?limit=5&offset=10")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json["notes"]), 1)
        self.assertEqual(self.connection.execute.call_args.args[1], (5, 10))

    def test_invalid_pagination(self):
        for query in ["limit=0", "limit=101", "offset=-1", "limit=no", "offset=99999999999"]:
            self.assertEqual(self.client.get("/notes?" + query).status_code, 400)
        self.connect.assert_not_called()

    def test_missing_note(self):
        self.connection.execute.return_value.fetchone.return_value = None
        self.assertEqual(self.client.get("/notes/999").status_code, 404)
        self.assertEqual(self.client.delete("/notes/999").status_code, 404)

    def test_retrieve_and_delete(self):
        self.connection.execute.return_value.fetchone.return_value = self.row
        self.assertEqual(self.client.get("/notes/1").json["title"], "Test")
        response = self.client.delete("/notes/1")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.data, b"")

    def test_database_failure_is_sanitized(self):
        self.connect.side_effect = psycopg.OperationalError("secret-password")
        for path in ["/health", "/notes"]:
            response = self.client.get(path)
            self.assertEqual(response.status_code, 503)
            self.assertNotIn("secret-password", response.get_data(as_text=True))

    def test_health_checks_schema(self):
        self.assertEqual(self.client.get("/health").status_code, 200)
        self.connection.execute.assert_called_once_with("SELECT id FROM notes LIMIT 1")


if __name__ == "__main__":
    unittest.main()
