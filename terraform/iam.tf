# One service account per job, each with only what it needs.

resource "google_service_account" "web" {
  account_id   = "run-web"
  display_name = "Cloud Run: web (public app + API + WebSockets)"
}

resource "google_service_account" "worker" {
  account_id   = "run-worker"
  display_name = "Cloud Run: worker service and jobs (internal)"
}

resource "google_service_account" "invoker" {
  account_id   = "run-invoker"
  display_name = "Calls the internal worker: Scheduler, Tasks, Pub/Sub push"
}

resource "google_service_account" "builder" {
  account_id   = "cloudbuild-builder"
  display_name = "Cloud Build: builds and pushes images"
}

resource "google_service_account" "deployer" {
  account_id   = "gh-deployer"
  display_name = "GitHub Actions in revenact-deploy: rolls out Cloud Run"
}

locals {
  runtime_roles = [
    "roles/aiplatform.user",
    "roles/cloudtrace.agent",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtasks.enqueuer",
  ]
}

resource "google_project_iam_member" "runtime" {
  for_each = {
    for pair in setproduct(["web", "worker"], local.runtime_roles) :
    "${pair[0]}/${pair[1]}" => { sa = pair[0], role = pair[1] }
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.sa == "web" ? google_service_account.web.email : google_service_account.worker.email}"
}

# Signed URLs for media are signed with IAM signBlob as the service itself.
resource "google_service_account_iam_member" "self_sign" {
  for_each = {
    web    = google_service_account.web
    worker = google_service_account.worker
  }

  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${each.value.email}"
}

# Web enqueues Cloud Tasks that run as the invoker identity.
resource "google_service_account_iam_member" "web_acts_as_invoker" {
  for_each = {
    web    = google_service_account.web.email
    worker = google_service_account.worker.email
  }

  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${each.value}"
}

resource "google_project_iam_member" "invoker_run" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.invoker.email}"
}

# Builder: push images, write build logs.
resource "google_artifact_registry_repository_iam_member" "builder_push" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.builder.email}"
}

resource "google_project_iam_member" "builder_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.builder.email}"
}

# Deployer: manage Cloud Run services and jobs, run them as the runtime
# accounts, read images.
resource "google_project_iam_member" "deployer_run" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_service_account_iam_member" "deployer_acts_as" {
  for_each = {
    web    = google_service_account.web.name
    worker = google_service_account.worker.name
  }

  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_artifact_registry_repository_iam_member" "deployer_pull" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

# Keyless GitHub login: only revenact-deploy's main branch can become the
# deployer. Pull requests (including from forks) cannot.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.event_name" = "assertion.event_name"
  }

  attribute_condition = "assertion.repository == '${var.github_owner}/${var.deploy_repo}' && assertion.ref == 'refs/heads/main' && assertion.event_name != 'pull_request' && assertion.event_name != 'pull_request_target'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.deploy_repo}"
}
