def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "healthy"


def test_readiness_ok(client):
    res = client.get("/healthz/ready")
    assert res.status_code == 200
    assert res.get_json()["db"] == "ok"


def test_login_requires_username(client):
    res = client.post("/login", json={})
    assert res.status_code == 400


def test_login_returns_token(client):
    res = client.post("/login", json={"username": "alice"})
    assert res.status_code == 200
    assert res.get_json()["token"] == "tok-alice"


def test_verify_valid_token(client):
    token = client.post("/login", json={"username": "bob"}).get_json()["token"]
    res = client.get("/verify", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.get_json()["username"] == "bob"


def test_verify_rejects_garbage(client):
    res = client.get("/verify", headers={"Authorization": "Bearer nope"})
    assert res.status_code == 401
