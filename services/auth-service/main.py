import json
import logging
import os
import sys

from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text

load_dotenv()

SERVICE_NAME = "auth-service"
TOKEN_PREFIX = "tok-"  # ponytail: mock token scheme; swap for real JWT if needed


# ── Structured logging (Cloud Logging reads the "severity" key) ──────────────
class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "severity": record.levelname,
            "service": SERVICE_NAME,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[_handler], force=True)
log = logging.getLogger(SERVICE_NAME)

app = Flask(__name__)
CORS(app)

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:////tmp/auth.db")
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(120), unique=True, nullable=False)


with app.app_context():
    try:
        db.create_all()
    except Exception as e:
        log.warning("DB not reachable at startup: %s", e)


@app.after_request
def log_request(response):
    log.info("%s %s -> %s", request.method, request.path, response.status_code)
    return response


@app.get("/api")
def api():
    return jsonify({"service": SERVICE_NAME, "status": "ok", "message": "Auth service operationnel"})


@app.get("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.get("/healthz/ready")
def readiness():
    try:
        db.session.execute(text("SELECT 1"))
        db.create_all()  # idempotent
        return jsonify({"status": "ready", "db": "ok"}), 200
    except Exception as e:
        log.error("readiness failed: %s", e)
        return jsonify({"status": "not ready", "db": str(e)}), 503


@app.post("/login")
def login():
    """Mock login: any username is accepted, recorded, and given a token."""
    data = request.get_json(silent=True) or request.form
    username = (data.get("username") or "").strip()
    if not username:
        return jsonify({"error": "username is required"}), 400

    if not User.query.filter_by(username=username).first():
        db.session.add(User(username=username))
        db.session.commit()
    log.info("login: %s", username)
    return jsonify({"token": f"{TOKEN_PREFIX}{username}", "username": username})


@app.get("/verify")
def verify():
    """Validate a bearer token. Used synchronously by task-service."""
    auth = request.headers.get("Authorization", "")
    token = auth.removeprefix("Bearer ").strip()
    if token.startswith(TOKEN_PREFIX) and len(token) > len(TOKEN_PREFIX):
        return jsonify({"valid": True, "username": token[len(TOKEN_PREFIX):]}), 200
    return jsonify({"valid": False}), 401
