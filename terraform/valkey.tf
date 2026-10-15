# Channel layer (multiplayer Copilot, notifications) and the rate-limit
# cache. Smallest node; reachable only inside the VPC.
resource "google_memorystore_instance" "valkey" {
  instance_id   = "revenact-valkey"
  location      = var.region
  mode          = "CLUSTER_DISABLED"
  node_type     = "SHARED_CORE_NANO"
  shard_count   = 1
  replica_count = 0

  authorization_mode      = "AUTH_DISABLED"
  transit_encryption_mode = "TRANSIT_ENCRYPTION_DISABLED"

  desired_auto_created_endpoints {
    network    = google_compute_network.vpc.id
    project_id = var.project_id
  }

  deletion_protection_enabled = false

  depends_on = [google_network_connectivity_service_connection_policy.valkey]
}
