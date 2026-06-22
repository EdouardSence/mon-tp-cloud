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

# S3 configuration — secrets come from the environment (.env locally, k8s Secret in prod).
# No credential defaults in source: a leaked key in git is a leaked key forever.
S3_BUCKET = os.environ.get("S3_BUCKET", "ynov-s3-bucket-esence-904639295906-eu-west-1-an")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")

s3_client = boto3.client(
    "s3",
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
)

# Database configuration
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:30432/uploads",
)
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)


class Upload(db.Model):
    __tablename__ = "uploads"

    id = db.Column(db.Integer, primary_key=True)
    filename = db.Column(db.String(255), nullable=False)
    s3_url = db.Column(db.Text, nullable=False)
    uploaded_at = db.Column(db.DateTime, nullable=False, default=lambda: datetime.now(UTC))


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
    return jsonify(
        {
            "service": "mon-tp-cloud",
            "status": "ok",
            "message": "Backend Cloud Run operationnel",
        }
    )


@app.get("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.post("/upload")
def upload():
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    try:
        s3_client.upload_fileobj(
            file,
            S3_BUCKET,
            file.filename,
            ExtraArgs={"ContentType": file.content_type},
        )
        region = "eu-west-1"
        url = f"https://{S3_BUCKET}.s3.{region}.amazonaws.com/{file.filename}"

        record = Upload(filename=file.filename, s3_url=url)
        db.session.add(record)
        db.session.commit()

        return jsonify({"url": url, "filename": file.filename}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500


@app.get("/uploads")
def list_uploads():
    rows = Upload.query.order_by(Upload.uploaded_at.desc()).all()
    return jsonify(
        [
            {
                "id": r.id,
                "filename": r.filename,
                "s3_url": r.s3_url,
                "uploaded_at": r.uploaded_at.isoformat(),
            }
            for r in rows
        ]
    )
