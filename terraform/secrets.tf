# Every secret lives in Secret Manager and is mounted into Cloud Run as an
# env var. Secrets Terraform can generate get their value here (state is in a
# private GCS bucket); secrets that come from outside (OAuth client secrets,
# the Gmail app password, the GitHub token) are created empty and filled with
# `gcloud secrets versions add`, so their values never touch this repo or
# the state.

resource "random_password" "django_secret_key" {
  length  = 64
  special = false
}

resource "random_bytes" "mail_token_key" {
  length = 32
}

locals {
  generated_secrets = {
    "django-secret-key" = random_password.django_secret_key.result
    "database-url"      = "postgres://${google_sql_user.app.name}:${random_password.db.result}@${google_sql_database_instance.db.private_ip_address}:5432/${google_sql_database.app.name}?sslmode=require"
    # A Fernet key is url-safe base64 of 32 random bytes.
    "mail-token-key" = replace(replace(random_bytes.mail_token_key.base64, "+", "-"), "/", "_")
  }

  manual_secrets = [
    "email-host-password",           # Gmail app password
    "email-host-user",               # the Gmail address it belongs to (kept out of this public repo)
    "google-oauth-client-secret",    # Gmail connections
    "slack-oauth-client-secret",     # Slack connector
    "slack-signing-secret",          # Slack interactivity (Send to Revenact) request signatures
    "atlassian-oauth-client-secret", # Jira connector
    "microsoft-oauth-client-secret", # Outlook (not in focus; empty is fine)
    "github-dispatch-token",         # Cloud Build -> revenact-deploy dispatch
    "alfee-demo-password",           # the judges' Alfee logins (seed-alfee job only)
    "platform-staff-password",       # the /platform staff superuser; read by people only, no runtime access
  ]

  # Which runtime service accounts may read which secrets.
  app_secrets = concat(keys(local.generated_secrets), [
    "email-host-password",
    "email-host-user",
    "google-oauth-client-secret",
    "slack-oauth-client-secret",
    "slack-signing-secret",
    "atlassian-oauth-client-secret",
    "microsoft-oauth-client-secret",
  ])
}

resource "google_secret_manager_secret" "generated" {
  for_each  = local.generated_secrets
  secret_id = each.key

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "generated" {
  for_each    = local.generated_secrets
  secret      = google_secret_manager_secret.generated[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret" "manual" {
  for_each  = toset(local.manual_secrets)
  secret_id = each.key

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

locals {
  all_secret_ids = merge(
    { for k, s in google_secret_manager_secret.generated : k => s.id },
    { for k, s in google_secret_manager_secret.manual : k => s.id },
  )
}

resource "google_secret_manager_secret_iam_member" "app" {
  for_each = {
    for pair in setproduct(local.app_secrets, ["web", "worker"]) :
    "${pair[0]}/${pair[1]}" => { secret = pair[0], sa = pair[1] }
  }

  secret_id = local.all_secret_ids[each.value.secret]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.sa == "web" ? google_service_account.web.email : google_service_account.worker.email}"
}

resource "google_secret_manager_secret_iam_member" "builder_dispatch" {
  secret_id = google_secret_manager_secret.manual["github-dispatch-token"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.builder.email}"
}

# Only the worker identity (the seed-alfee job) reads the demo password.
resource "google_secret_manager_secret_iam_member" "seed_password" {
  secret_id = google_secret_manager_secret.manual["alfee-demo-password"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker.email}"
}

# Created by hand on 2026-10-17 to bootstrap the first platform staff account.
import {
  to = google_secret_manager_secret.manual["platform-staff-password"]
  id = "projects/revenact-prod/secrets/platform-staff-password"
}
