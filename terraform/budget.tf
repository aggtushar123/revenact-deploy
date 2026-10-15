resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "revenact-prod monthly"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
    # Count spend before credits, so the alerts warn while credits are still
    # covering it.
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.8
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  depends_on = [google_project_service.apis]
}
