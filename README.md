# revenact-deploy

How Revenact runs on Google Cloud. The application source lives in private
repositories; this public repository holds only the infrastructure (Terraform)
and the release pipeline, and records which image digest is live.

```
private repo push to main
  └─ Cloud Build: docker build → Artifact Registry (asia-south1, private)
       └─ repository_dispatch "image-built" {component, image@sha256}
            └─ this repo, .github/workflows/deploy.yml
                 ├─ commit digest to releases/<component>.txt
                 ├─ keyless login (Workload Identity Federation, main only)
                 ├─ Cloud Run Job: migrate (backend images)
                 ├─ Cloud Run: revenact-web (nginx + Django sidecar)
                 └─ smoke test, roll back on failure
```

## Runtime

| Piece | Service |
|---|---|
| App, API, WebSockets | Cloud Run `revenact-web`: nginx ingress (React build) + Daphne sidecar, one origin |
| Database | Cloud SQL PostgreSQL 16 (pgvector), private IP only, TLS required |
| Channel layer, cache | Memorystore for Valkey, private (PSC) |
| Files | Cloud Storage, private, uniform access |
| AI | Vertex AI Gemini (no API keys; Cloud Run's service account) |
| Secrets | Secret Manager, one secret per value, per-service access |
| Batch | Cloud Run Jobs started by Cloud Scheduler |

Region: `asia-south1` (Mumbai). Project: `revenact-prod`.

## Layout

- `terraform/`: everything except the Cloud Run services and jobs themselves.
- `services/`: Cloud Run service and job definitions; `env.yaml` is the shared Django environment (secrets are references only).
- `scripts/render.py`: fills image digests and environment into `build/`.
- `releases/`: the digest currently deployed for each component.

## First-time setup (owner)

```sh
# State bucket (once)
gcloud storage buckets create gs://revenact-prod-tfstate --location asia-south1 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://revenact-prod-tfstate --versioning

cd terraform
echo 'billing_account = "XXXXXX-XXXXXX-XXXXXX"' > terraform.tfvars
terraform init && terraform apply

# Cloud Build ↔ GitHub (browser OAuth, once), then create the build triggers
gcloud builds connections create github revenact-github --region asia-south1
terraform apply -var github_connection=projects/revenact-prod/locations/asia-south1/connections/revenact-github

# Secrets Terraform cannot generate
printf '%s' "$VALUE" | gcloud secrets versions add email-host-password --data-file=-
printf '%s' "$VALUE" | gcloud secrets versions add github-dispatch-token --data-file=-
printf '%s' "$VALUE" | gcloud secrets versions add google-oauth-client-secret --data-file=-
printf '%s' "$VALUE" | gcloud secrets versions add slack-oauth-client-secret --data-file=-
```

`github-dispatch-token` is a fine-grained GitHub token limited to this
repository with **Contents: read and write**.

## Security notes

- Nothing has a public IP except the Cloud Run URL. No ingress firewall rules.
- Only `main` of this repository can obtain the deployer identity; pull
  requests cannot. No long-lived keys exist anywhere.
- The deployer can only roll out Cloud Run; infrastructure changes are applied
  by the owner.
- Images are referenced by digest, never by tag.
