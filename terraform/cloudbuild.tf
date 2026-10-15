# Builds run in Cloud Build because the private repos' GitHub Actions are
# billing-blocked. The GitHub connection needs a one-time browser OAuth, so it
# is created with gcloud (README) and only referenced here by name.

resource "google_cloudbuildv2_repository" "source" {
  for_each = var.github_connection == "" ? {} : var.source_repos

  name              = each.value
  location          = var.region
  parent_connection = var.github_connection
  remote_uri        = "https://github.com/${var.github_owner}/${each.value}.git"
}

resource "google_cloudbuild_trigger" "image" {
  for_each = google_cloudbuildv2_repository.source

  name            = "${each.key}-main"
  location        = var.region
  description     = "Build ${each.key} on push to main, push to Artifact Registry, dispatch a deploy"
  service_account = google_service_account.builder.id
  filename        = "cloudbuild.yaml"

  repository_event_config {
    repository = each.value.id
    push {
      branch = "^main$"
    }
  }
}
