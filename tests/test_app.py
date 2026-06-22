import io

import main


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "healthy"


def test_api(client):
    res = client.get("/api")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"


def test_list_todos_empty(client):
    res = client.get("/todos")
    assert res.status_code == 200
    assert res.get_json() == []


def test_create_todo_no_title(client):
    res = client.post("/todos", data={})
    assert res.status_code == 400


def test_create_todo_minimal(client):
    res = client.post("/todos", data={"title": "Buy milk"})
    assert res.status_code == 201
    data = res.get_json()
    assert data["title"] == "Buy milk"
    assert data["status"] == "pending"
    assert data["file_url"] is None


def test_create_todo_appears_in_list(client):
    client.post("/todos", data={"title": "Task A"})
    res = client.get("/todos")
    assert len(res.get_json()) == 1


def test_update_status(client):
    r = client.post("/todos", data={"title": "Task"})
    todo_id = r.get_json()["id"]
    res = client.patch(f"/todos/{todo_id}", json={"status": "done"})
    assert res.status_code == 200
    assert res.get_json()["status"] == "done"


def test_delete_todo(client):
    r = client.post("/todos", data={"title": "To delete"})
    todo_id = r.get_json()["id"]
    res = client.delete(f"/todos/{todo_id}")
    assert res.status_code == 204
    assert client.get("/todos").get_json() == []


def test_create_todo_with_file(client, monkeypatch):
    monkeypatch.setattr(main.s3_client, "upload_fileobj", lambda *a, **k: None)
    data = {"title": "With attachment", "file": (io.BytesIO(b"hello"), "doc.txt")}
    res = client.post("/todos", data=data, content_type="multipart/form-data")
    assert res.status_code == 201
    assert res.get_json()["file_url"] is not None
