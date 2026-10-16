variable "project_id" {
  type    = string
  default = "revenact-prod"
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "billing_account" {
  description = "Billing account the project is linked to (budget lives there)."
  type        = string
}

# In the billing account's own currency (INR; a budget in any other
# currency is refused). About USD 100.
variable "monthly_budget_inr" {
  type    = number
  default = 8800
}

variable "github_owner" {
  type    = string
  default = "aggtushar123"
}

variable "deploy_repo" {
  description = "The public repo whose main branch may deploy to Cloud Run."
  type        = string
  default     = "revenact-deploy"
}

variable "source_repos" {
  description = "Private source repos Cloud Build builds images from, by component."
  type        = map(string)
  default = {
    backend  = "revenact-backend"
    frontend = "revenact-frontend"
  }
}

variable "github_connection" {
  description = "Name of the Cloud Build GitHub connection, created once with gcloud (needs a browser OAuth step). Empty until then; triggers are only created once it is set."
  type        = string
  default     = "projects/revenact-prod/locations/asia-south1/connections/revenact-github"
}

variable "db_tier" {
  description = "Cloud SQL machine type. db-g1-small normally; db-custom-1-3840 for a judging window."
  type        = string
  default     = "db-g1-small"
}
