terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Created once by hand (see README): versioned, uniform access, no public access.
  backend "gcs" {
    bucket = "revenact-prod-tfstate"
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Billing budgets and a few other APIs need a quota project when called
  # with user credentials.
  user_project_override = true
  billing_project       = var.project_id
}
