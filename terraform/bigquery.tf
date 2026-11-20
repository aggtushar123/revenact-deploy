# The analytics warehouse. The nightly job (backend services/warehouse,
# `sync_warehouse`) replaces its tables with de-identified copies of the
# database (numbers, dates and categories; no names, emails or text), trains
# one BigQuery ML churn model per tenant here, and writes the scores back to
# Cloud SQL. The app never queries BigQuery on a request.
resource "google_bigquery_dataset" "warehouse" {
  dataset_id    = "revenact_warehouse"
  friendly_name = "Alfred warehouse"
  description   = "Nightly de-identified copy of the app database, churn models and AI usage views."
  location      = var.region

  # Replaced in full every night; nothing here is the only copy.
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

# Only the worker (which runs the nightly job) reads or writes it. The web
# service has no BigQuery access at all.
resource "google_bigquery_dataset_iam_member" "worker_edit" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.worker.email}"
}

# Running a query, load or CREATE MODEL is a job, and jobs are project-level.
# jobUser grants no data access by itself.
resource "google_project_iam_member" "worker_bigquery_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.worker.email}"
}
