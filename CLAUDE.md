# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Todo-List app split into **3 microservices**, each its own Docker image, deployed to **Google Cloud Run** via Terraform:

- **`frontend`** (`services/frontend/`) — static HTML/JS served by nginx. Talks to the backends from the browser; backend URLs are injected at container start (`config.js` via envsubst) and CORS handles cross-origin.
- **`auth-service`** (`services/auth-service/`) — Flask API, mock authentication. `POST /login` records the user (Postgres) and returns a `tok-<user>` token; `GET /verify` validates it.
- **`task-service`** (`services/task-service/`) — Flask API for todos (Postgres) + file attachments (S3). On mutating routes it calls `auth-service /verify` **synchronously** when `AUTH_SERVICE_URL` is set.

Both backends expose `GET /healthz/ready` (active Postgres `SELECT 1` → 200, else 503) used as the Cloud Run startup probe.

## Commands

```bash
# Full stack locally (3 services + Postgres) — open http://localhost:8080
docker compose up --build

# Run one backend bare (sqlite fallback)
cd services/task-service && pip install -r requirements.txt
gunicorn --bind 0.0.0.0:8080 main:app

# Lint (whole repo) + tests (per service — what CI runs)
ruff check .
cd services/auth-service && pytest -q
cd services/task-service && pytest -q
```

Each backend is a single-file Flask app (`main.py`) with its own `requirements.txt`, `Dockerfile`, `pytest.ini`, `conftest.py`, `tests/`. No blueprints.

**S3** (task-service): boto3 client from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `S3_BUCKET`. Bucket in `eu-west-1`; URLs are `https://{bucket}.s3.{region}.amazonaws.com/{filename}`.

**Logging**: both backends emit structured JSON to stdout with a `severity` key → picked up natively by Cloud Logging. Cloud Run collects request/latency metrics automatically.

## CI/CD (GitHub Actions)

`.github/workflows/ci-cd.yml`, on every push and PR:
- **CI, parallel**: `lint` (ruff over repo) and `test` (pytest, matrix over `auth-service` + `task-service`) — no `needs:` between them.
- **CD** (push to `develop`/`main` only, gated on lint+test): `build-and-push` matrix builds the **3 images independently** and pushes them to **Artifact Registry** tagged with the commit SHA (+ `latest`), then `terraform apply -auto-approve` for the matching env.
- `develop` → dev, `main` → prod. `deploy-*` use GitHub `environment:` for protection + audit.

Required secrets: `GCP_SA_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. Images: `europe-west1-docker.pkg.dev/mon-tp-cloud/docker/{frontend,auth-service,task-service}`.

## Multi-environment Terraform

- `terraform/modules/service/` — generic, reusable Cloud Run v2 service (image, env, scaling, startup probe on a configurable path, optional AWS secrets created only when creds are passed).
- `terraform/modules/environment/` — composes the `service` module **3×** for one env; scaling derived from `environment`.
- `terraform/environments/{dev,prod}/` — thin roots passing the 3 image vars + AWS creds. Prod uses the GCS remote backend.

```bash
terraform -chdir=terraform/environments/dev  init && terraform -chdir=.../dev  apply -auto-approve
terraform -chdir=terraform/environments/prod init && terraform -chdir=.../prod apply -auto-approve
```

| | service names | replicas (min/max) | CPU | probe |
|---|---|---|---|---|
| **dev** | `mon-tp-cloud-{svc}-dev` | backends 0–3, front 0–2 | idle-throttled | `/healthz/ready` (front `/health`) |
| **prod** | `mon-tp-cloud-{svc}` | backends 1–10, front 1–5 | always-on (zero-downtime) | same |

The CD pipeline overrides `TF_VAR_{frontend,auth,task}_image` with the SHA tag.

**Database**: `terraform/modules/database/` provisions a Cloud SQL Postgres instance, gated by `enable_cloud_sql` (default **false** in both envs → no cost). When false, backends use the in-container sqlite fallback. When true, the module is wired automatically: instance attached to Cloud Run via the `/cloudsql` socket and `DATABASE_URL` injected. Set `TF_VAR_db_password` + flip the flag to provision.

> **Legacy** (not in the active path): `k8s/` manifests and `terraform/environments/minikube/` from the earlier single-image Kubernetes exercise are kept for reference.

> **Security:** the AWS key formerly hardcoded was exposed in git history — **rotate it**. Creds now come only from env / Secret Manager. `terraform.tfstate` stores secrets in plaintext (dev is local state) — prod uses the GCS backend; use an encrypted remote backend for real prod.
