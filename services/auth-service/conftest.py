import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import main  # noqa: E402
import pytest  # noqa: E402


@pytest.fixture
def client():
    main.app.config.update(TESTING=True)
    with main.app.app_context():
        main.db.drop_all()
        main.db.create_all()
        with main.app.test_client() as c:
            yield c
