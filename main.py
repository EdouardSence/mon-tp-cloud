import os
from datetime import UTC, datetime

import boto3
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

load_dotenv()

app = Flask(__name__, static_folder=".")
CORS(app)

S3_BUCKET = os.environ.get("S3_BUCKET", "ynov-s3-bucket-esence-904639295906-eu-west-1-an")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")

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
        print(f"WARNING: DB not reachable at startup: {e}")


@app.route("/")
def root():
    return send_from_directory(".", "index.html")


@app.get("/api")
def api():
    return jsonify({"service": "mon-tp-cloud", "status": "ok", "message": "Backend Cloud Run operationnel"})


@app.get("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.get("/todos")
def list_todos():
    rows = Todo.query.order_by(Todo.created_at.desc()).all()
    return jsonify([t.to_dict() for t in rows])


@app.post("/todos")
def create_todo():
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
            return jsonify({"error": f"S3 upload failed: {e}"}), 500

    todo = Todo(title=title, description=description, file_url=file_url)
    db.session.add(todo)
    db.session.commit()
    return jsonify(todo.to_dict()), 201


@app.patch("/todos/<int:todo_id>")
def update_todo(todo_id):
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
    todo = db.get_or_404(Todo, todo_id)
    db.session.delete(todo)
    db.session.commit()
    return "", 204
