# Background work without an always-on worker. On Cloud Run nothing runs
# between requests, so every old sleep loop is a Cloud Scheduler job that
# POSTs to the web service's tick endpoint (backend core/ticks.py) with an
# OIDC token signed as run-invoker; the backend checks the audience and the
# account and holds an advisory lock per task. Gmail's push arrives through
# Pub/Sub and syncs the woken mailbox inside that request.

locals {
  web_url       = "https://revenact-web-${data.google_project.this.number}.${var.region}.run.app"
  tick_audience = "${local.web_url}/api/v1/internal/tick/"
  push_audience = "${local.web_url}/api/v1/mail/google/push/"

  ticks = {
    # A DB check each minute; Gmail itself is called only when a push, a
    # queued reply or Sync now woke the mailbox, or the 30-minute backstop.
    mail    = { schedule = "* * * * *", deadline = "300s" }
    deliver = { schedule = "* * * * *", deadline = "300s" }
    agents  = { schedule = "*/5 * * * *", deadline = "600s" }
    tickets = { schedule = "*/10 * * * *", deadline = "600s" }
  }
}

resource "google_cloud_scheduler_job" "tick" {
  for_each = local.ticks

  name             = "tick-${each.key}"
  region           = var.region
  schedule         = each.value.schedule
  time_zone        = "Etc/UTC"
  attempt_deadline = each.value.deadline

  # The next tick is the retry.
  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"
    uri         = "${local.tick_audience}${each.key}/"

    oidc_token {
      service_account_email = google_service_account.invoker.email
      audience              = local.tick_audience
    }
  }

  depends_on = [google_project_service.apis]
}

# The nightly batch is a Cloud Run Job (services/jobs/nightly.yaml), started
# through the Run Admin API.
resource "google_cloud_scheduler_job" "nightly" {
  name             = "nightly"
  region           = var.region
  schedule         = "30 1 * * *"
  time_zone        = "Etc/UTC"
  attempt_deadline = "60s"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/revenact-nightly:run"

    oauth_token {
      service_account_email = google_service_account.invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.apis]
}

# --- Gmail push -----------------------------------------------------------------

resource "google_pubsub_topic" "gmail" {
  name                       = "gmail-push"
  message_retention_duration = "86400s"

  depends_on = [google_project_service.apis]
}

# Only Gmail may publish (users.watch names this topic).
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  topic  = google_pubsub_topic.gmail.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

resource "google_pubsub_subscription" "gmail_push" {
  name  = "gmail-push-web"
  topic = google_pubsub_topic.gmail.id

  # The push syncs the mailbox inside the request.
  ack_deadline_seconds       = 120
  message_retention_duration = "3600s"

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  push_config {
    push_endpoint = local.push_audience

    oidc_token {
      service_account_email = google_service_account.invoker.email
      audience              = local.push_audience
    }
  }
}

# Pub/Sub's service agent signs the push's OIDC token as run-invoker.
resource "google_service_account_iam_member" "pubsub_signs_as_invoker" {
  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.gmail]
}
