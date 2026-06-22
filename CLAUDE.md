# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flask app deployed on Google Cloud Run. Serves a static frontend (`index.html`) and exposes a REST API that uploads files to AWS S3.

## Minikube PostgreSQL setup

```bash
# Start minikube (once)
minikube start

# Deploy PostgreSQL
kubectl apply -f k8s/postgres.yaml

# Get minikube IP — use in DATABASE_URL
minikube ip

# Check postgres pod is running
kubectl get pods -l app=postgres

# Update .env with real IP
# DATABASE_URL=postgresql://postgres:postgres@<minikube-ip>:30432/uploads
```

PostgreSQL is exposed on NodePort **30432**. The `uploads` table is auto-created on first Flask startup via `db.create_all()`.

## Commands

```bash
# Run locally
pip install -r requirements.txt
flask --app main run --port 8080

# Or with gunicorn (matches production)
gunicorn --bind 0.0.0.0:8080 main:app

# Lint + unit tests (what CI runs)
pip install -r requirements-dev.txt
ruff check .
pytest -q

# Docker
docker build -t mon-tp-cloud .
docker run -p 8080:8080 --env-file .env mon-tp-cloud

# Deploy to Cloud Run
gcloud run deploy mon-tp-cloud --source . --region europe-west1

# Deploy to App Engine
gcloud app deploy
```

## Architecture

Single-file app (`main.py`). No routing modules, no blueprints.

- `GET /` — serves `index.html` (static frontend)
- `GET /api` — service info JSON
- `GET /health` — health check
- `POST /upload` — uploads multipart file to S3, returns public URL

**S3**: boto3 client initialized at module level using env vars. Bucket is in `eu-west-1`. Returned URLs follow `https://{bucket}.s3.{region}.amazonaws.com/{filename}`.

**Config**: env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET`. Loaded from `.env` via `load_dotenv()` (gitignored). No credential defaults in `main.py` — missing creds fall through to boto3's default chain. `.env.example` lists the required vars.

**Deployment targets**:
- `Dockerfile` + `Procfile` → Cloud Run (port 8080, gunicorn)
- `app.yaml` → App Engine standard (python312, F1 instance) — note: currently configured as static-only handlers, dynamic routes won't work without adding a `script: auto` handler
- `terraform/` → minikube Kubernetes, segmented into `dev` / `prod` environments (see below)

## CI/CD (GitHub Actions)

`.github/workflows/ci-cd.yml` runs on every push and PR:
- **CI** (`ubuntu-latest`, isolated): `lint` (ruff) + `test` (pytest).
- **CD** (only on push to `develop`/`main`, gated on CI via `needs:`): build backend + frontend images, push to GHCR tagged with the commit SHA, then `terraform apply -auto-approve` for the matching env.
- `develop` → dev env, `main` → prod env. The `deploy-*` jobs use `environment:` (GitHub Environments) for protection rules + audit trail, and must run on a **self-hosted runner** with kubeconfig access to the minikube cluster.

Required GitHub Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (GHCR push uses the built-in `GITHUB_TOKEN`).

## Multi-environment Terraform

`terraform/modules/app/` is a reusable stack (postgres + backend + frontend). Each env instantiates it in its own k8s **namespace**:

```bash
# Local dev apply (uses locally-built minikube images, image_pull_policy=Never)
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev apply -auto-approve

# Prod (registry images, 2 replicas, zero-downtime rolling update)
terraform -chdir=terraform/environments/prod apply -auto-approve
```

| | namespace | replicas | NodePort | images |
|---|---|---|---|---|
| **dev** | `dev` | 1 | 30080 | local (`Never`) |
| **prod** | `prod` | 2 | 30090 | GHCR `:sha`, rolling update `maxUnavailable=0` + readiness probes |

Replace `OWNER` in `terraform/environments/prod/main.tf` with the GitHub org/user. The CD pipeline overrides `TF_VAR_backend_image` / `TF_VAR_frontend_image` with the freshly-built SHA tag.

> **Security:** the AWS key formerly hardcoded in `main.py`/`.env` was exposed in this repo's history — **rotate it**. Credentials now come only from env / k8s Secrets. Note `terraform.tfstate` stores Secret values in plaintext, so it is gitignored (use a remote encrypted backend for real prod).
