from fastapi.testclient import TestClient

from iqana_demo.api.app import app  # adjust import if your FastAPI app is elsewhere


def test_health_ok():
    client = TestClient(app)  # type: ignore  # noqa: PGH003
    r = client.get("/health")
    assert r.status_code == 200  # noqa: PLR2004
    body = r.json()
    assert {"name", "version", "time"} <= body.keys()
