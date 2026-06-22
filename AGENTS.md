# AGENTS.md

## Architecture

Single-file Flask app (`main.py`), no routing modules, no blueprints.

Routes:
- `GET /` — serves `index.html`
- `GET /api` — service info JSON
- `GET /health` — health check
- `POST /upload` — multipart file upload to S3, returns public URL

S3: boto3 client at module level, bucket in `eu-west-1`. URLs: `https://{bucket}.s3.{region}.amazonaws.com/{filename}`.

## Commands

```bash
# Local dev
pip install -r requirements.txt
flask --app main run --port 8080

# Lint + tests (CI)
pip install -r requirements-dev.txt
ruff check .
pytest -q

# Docker + Cloud Run
docker build -t mon-tp-cloud .
gcloud run deploy mon-tp-cloud --source . --region europe-west1
```

## CI/CD

`.github/workflows/ci-cd.yml`:
- CI on every push/PR: `ruff` + `pytest`
- CD on push to `develop`/`main`: builds images, pushes to GHCR (`:sha`), then `terraform apply` for matching env
- `develop` → dev namespace, `main` → prod namespace
- Deploy jobs require self-hosted runner with kubeconfig

## Terraform

`terraform/modules/app/` is reusable (postgres + backend + frontend). Each env inits in its own namespace:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev apply -auto-approve
terraform -chdir=terraform/environments/prod apply -auto-approve
```

| env | namespace | replicas | NodePort | images |
|-----|-----------|----------|----------|--------|
| dev | `dev` | 1 | 30080 | local (`Never`) |
| prod | `prod` | 2 | 30090 | GHCR `:sha`, rolling `maxUnavailable=0` |

Replace `OWNER` in `terraform/environments/prod/main.tf` with your GitHub org/user. CD pipeline sets `TF_VAR_backend_image` / `TF_VAR_frontend_image` to the SHA tag.

## Security

AWS key was exposed in repo history — **rotate it**. Credentials now via env / k8s Secrets only. `terraform.tfstate` stores Secret values in plaintext, so it's gitignored; use remote encrypted backend for real prod.

## Config

`.env` via `load_dotenv()` (gitignored). Required: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET`. See `.env.example`.
