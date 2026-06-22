import os

# Force a throwaway in-memory DB and dummy creds before the app imports.
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
os.environ.setdefault("S3_BUCKET", "test-bucket")

import pytest  # noqa: E402

import main  # noqa: E402


@pytest.fixture
def client():
    main.app.config.update(TESTING=True)
    with main.app.app_context():
        main.db.drop_all()
        main.db.create_all()
        with main.app.test_client() as c:
            yield c
