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

# CI: every pull request to main runs the repo's cloudbuild-ci.yaml (lint and
# the tests) and cloudbuild-soc2.yaml (the SOC 2 security gates: gitleaks,
# dependency audit, semgrep, trivy, the heuristic scan). No secrets, nothing
# pushed. The Cloud Build GitHub app reports each build on the PR as a check.
# The backend suite runs as 4 shards, one build (and one 8-core machine) each.
# Pull requests from people without write access wait for a maintainer's
# `/gcbrun` comment. These replace the repos' GitHub Actions workflows.
locals {
  ci_builds = merge(
    { for n in range(1, 5) : "backend-pr-${n}" => { repo = "backend", file = "cloudbuild-ci.yaml", subs = { _SHARD = tostring(n), _SHARDS = "4" } } },
    { "frontend-pr" = { repo = "frontend", file = "cloudbuild-ci.yaml", subs = {} } },
    { "backend-soc2" = { repo = "backend", file = "cloudbuild-soc2.yaml", subs = {} } },
    { "frontend-soc2" = { repo = "frontend", file = "cloudbuild-soc2.yaml", subs = {} } },
  )
}

resource "google_cloudbuild_trigger" "pr" {
  for_each = var.github_connection == "" ? {} : local.ci_builds

  name            = each.key
  location        = var.region
  description     = "CI for ${each.value.repo} pull requests to main"
  service_account = google_service_account.builder.id
  filename        = each.value.file
  substitutions   = each.value.subs

  repository_event_config {
    repository = google_cloudbuildv2_repository.source[each.value.repo].id
    pull_request {
      branch          = "^main$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}
