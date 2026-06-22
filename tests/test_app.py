import io

import main


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "healthy"


def test_api(client):
    r = client.get("/api")
    assert r.status_code == 200
    assert r.get_json()["service"] == "mon-tp-cloud"


def test_upload_requires_file(client):
    assert client.post("/upload").status_code == 400


def test_upload_rejects_empty_filename(client):
    data = {"file": (io.BytesIO(b"x"), "")}
    r = client.post("/upload", data=data, content_type="multipart/form-data")
    assert r.status_code == 400


def test_upload_persists_and_lists(client, monkeypatch):
    # Don't hit real S3 — the upload path is what we're testing, not boto3.
    monkeypatch.setattr(main.s3_client, "upload_fileobj", lambda *a, **k: None)

    data = {"file": (io.BytesIO(b"hello"), "note.txt")}
    r = client.post("/upload", data=data, content_type="multipart/form-data")
    assert r.status_code == 200, r.get_json()
    assert r.get_json()["filename"] == "note.txt"

    rows = client.get("/uploads").get_json()
    assert any(row["filename"] == "note.txt" for row in rows)
