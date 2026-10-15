resource "google_artifact_registry_repository" "images" {
  repository_id = "revenact"
  location      = var.region
  format        = "DOCKER"
  description   = "Revenact backend and frontend images (private)."

  cleanup_policy_dry_run = false

  # Keep the last 10 images of each component, so rollback stays possible,
  # and drop anything older than two weeks beyond that.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "1209600s"
    }
  }

  depends_on = [google_project_service.apis]
}
