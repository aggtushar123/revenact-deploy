# Uploaded files (Files tab, call transcripts). Private: only the backend's
# service accounts can read or write, and users get them through the app's
# authenticated download view.
resource "google_storage_bucket" "media" {
  name                        = "${var.project_id}-media"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "media_rw" {
  for_each = {
    web    = google_service_account.web.email
    worker = google_service_account.worker.email
  }

  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${each.value}"
}
