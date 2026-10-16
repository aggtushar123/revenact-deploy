# Production visibility (2026-10-16: blank Copilot replies and failed
# connects were found by people, not systems). Cloud Monitoring only, no new
# vendor: an uptime check on the health endpoint, and alerts on server
# errors, error logs, the uptime check and a Copilot evaluation regression.

resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert_emails)
  display_name = "Revenact alerts: ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }

  depends_on = [google_project_service.apis]
}

locals {
  alert_channels = [for c in google_monitoring_notification_channel.email : c.id]
  web_host       = trimprefix(local.web_url, "https://")
}

resource "google_monitoring_uptime_check_config" "health" {
  display_name = "revenact-web health"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path         = "/api/v1/health/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = local.web_host
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "uptime" {
  display_name          = "Revenact is down (health check failing)"
  combiner              = "OR"
  notification_channels = local.alert_channels

  conditions {
    display_name = "Health check failing from 2+ regions"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.health.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
      trigger { count = 1 }
    }
  }
}

resource "google_monitoring_alert_policy" "server_errors" {
  display_name          = "Revenact web: 5xx responses"
  combiner              = "OR"
  notification_channels = local.alert_channels

  conditions {
    display_name = "More than 10 5xx responses in 5 minutes"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"revenact-web\" AND metric.label.response_code_class=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }
}

resource "google_monitoring_alert_policy" "error_logs" {
  display_name          = "Revenact: application errors logged"
  combiner              = "OR"
  notification_channels = local.alert_channels

  conditions {
    display_name = "ERROR logs from the web service or jobs"
    condition_matched_log {
      # The app logs JSON with "level", which Cloud Logging does not read as
      # severity (backend follow-up: also write "severity"): match both.
      filter = "(resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"revenact-web\" OR resource.type=\"cloud_run_job\") AND (severity>=ERROR OR jsonPayload.level=\"ERROR\" OR jsonPayload.level=\"CRITICAL\")"
    }
  }

  # A burst of errors is one notification, at most every 30 minutes.
  alert_strategy {
    notification_rate_limit { period = "1800s" }
    auto_close = "3600s"
  }
}

resource "google_monitoring_alert_policy" "copilot_eval_regressed" {
  display_name          = "Copilot evaluation regressed"
  combiner              = "OR"
  notification_channels = local.alert_channels

  conditions {
    display_name = "Nightly golden set scored below the previous run"
    condition_matched_log {
      filter = "resource.type=\"cloud_run_job\" AND (textPayload:\"copilot eval regressed\" OR jsonPayload.message:\"copilot eval regressed\")"
    }
  }

  alert_strategy {
    notification_rate_limit { period = "3600s" }
    auto_close = "86400s"
  }
}
