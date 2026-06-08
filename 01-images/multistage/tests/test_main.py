from main import app


def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200


def test_index():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
