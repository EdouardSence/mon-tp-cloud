import json
import logging
import os
import sys
from datetime import UTC, datetime

import boto3
import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text

load_dotenv()

SERVICE_NAME = "task-service"


# ── Structured logging (Cloud Logging reads the "severity" key) ──────────────
# ponytail: ~15 lines duplicated in auth-service; a shared pkg would need its own
# build/packaging across separate Docker contexts. Duplicate beats that here.
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

S3_BUCKET = os.environ.get("S3_BUCKET", "ynov-s3-bucket-esence-904639295906-eu-west-1-an")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")

# Synchronous auth: when set, mutating routes verify the bearer token against
# auth-service. Unset (tests / standalone local) => verification skipped.
AUTH_SERVICE_URL = os.environ.get("AUTH_SERVICE_URL")

s3_client = boto3.client(
    "s3",
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
)

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:////tmp/todos.db")
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)


class Todo(db.Model):
    __tablename__ = "todos"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(255), nullable=False)
    description = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), nullable=False, default="pending")
    file_url = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(UTC))

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "status": self.status,
            "file_url": self.file_url,
            "created_at": self.created_at.isoformat(),
        }


with app.app_context():
    try:
        db.create_all()
    except Exception as e:
        log.warning("DB not reachable at startup: %s", e)


@app.after_request
def log_request(response):
    log.info("%s %s -> %s", request.method, request.path, response.status_code)
    return response


def authorized():
    """Synchronous call to auth-service to validate the caller's token."""
    if not AUTH_SERVICE_URL:
        return True  # ponytail: auth not wired (tests/local) => allow
    try:
        r = requests.get(
            f"{AUTH_SERVICE_URL}/verify",
            headers={"Authorization": request.headers.get("Authorization", "")},
            timeout=3,
        )
        return r.status_code == 200
    except requests.RequestException as e:
        log.warning("auth-service unreachable: %s", e)
        return False


@app.get("/api")
def api():
    return jsonify({"service": SERVICE_NAME, "status": "ok", "message": "Task service operationnel"})


@app.get("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.get("/healthz/ready")
def readiness():
    try:
        db.session.execute(text("SELECT 1"))
        db.create_all()  # idempotent — creates missing tables if startup failed
        return jsonify({"status": "ready", "db": "ok"}), 200
    except Exception as e:
        log.error("readiness failed: %s", e)
        return jsonify({"status": "not ready", "db": str(e)}), 503


@app.get("/todos")
def list_todos():
    rows = Todo.query.order_by(Todo.created_at.desc()).all()
    return jsonify([t.to_dict() for t in rows])


@app.post("/todos")
def create_todo():
    if not authorized():
        return jsonify({"error": "unauthorized"}), 401

    title = request.form.get("title", "").strip()
    if not title:
        return jsonify({"error": "title is required"}), 400

    description = request.form.get("description", "").strip() or None
    file_url = None

    file = request.files.get("file")
    if file and file.filename:
        try:
            s3_client.upload_fileobj(
                file,
                S3_BUCKET,
                file.filename,
                ExtraArgs={"ContentType": file.content_type},
            )
            region = "eu-west-1"
            file_url = f"https://{S3_BUCKET}.s3.{region}.amazonaws.com/{file.filename}"
        except Exception as e:
            log.error("S3 upload failed: %s", e)
            return jsonify({"error": f"S3 upload failed: {e}"}), 500

    todo = Todo(title=title, description=description, file_url=file_url)
    db.session.add(todo)
    db.session.commit()
    return jsonify(todo.to_dict()), 201


@app.patch("/todos/<int:todo_id>")
def update_todo(todo_id):
    if not authorized():
        return jsonify({"error": "unauthorized"}), 401
    todo = db.get_or_404(Todo, todo_id)
    data = request.get_json(silent=True) or {}
    if "status" in data:
        todo.status = data["status"]
    if "title" in data:
        todo.title = data["title"]
    if "description" in data:
        todo.description = data["description"]
    db.session.commit()
    return jsonify(todo.to_dict())


@app.delete("/todos/<int:todo_id>")
def delete_todo(todo_id):
    if not authorized():
        return jsonify({"error": "unauthorized"}), 401
    todo = db.get_or_404(Todo, todo_id)
    db.session.delete(todo)
    db.session.commit()
    return "", 204
