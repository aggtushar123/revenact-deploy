# One private VPC. Cloud Run reaches it with Direct VPC egress (no connector,
# no NAT: only private ranges go through the VPC, public traffic such as
# Gmail/Slack/Jira APIs leaves Cloud Run directly). Nothing in here has a
# public IP and there are no ingress firewall rules.
resource "google_compute_network" "vpc" {
  name                    = "revenact-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "run" {
  name                     = "revenact-run"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

# Private services access: Cloud SQL gets a private IP from this range.
resource "google_compute_global_address" "private_services" {
  name          = "revenact-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

# Memorystore for Valkey is reached through Private Service Connect; this
# policy lets it create its endpoint in the run subnet.
resource "google_network_connectivity_service_connection_policy" "valkey" {
  name          = "revenact-valkey"
  location      = var.region
  service_class = "gcp-memorystore"
  network       = google_compute_network.vpc.id

  psc_config {
    subnetworks = [google_compute_subnetwork.run.id]
  }

  depends_on = [google_project_service.apis]
}
