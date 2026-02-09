# ──────────────────────────────────────────────
# Budget — catch any accidental charges
# ──────────────────────────────────────────────
# All resources are Always Free; monthly spend should be $0.
# Budget is set to $1 USD so any non-zero charge triggers alerts.

resource "oci_budget_budget" "always_free" {
  compartment_id         = var.tenancy_ocid
  amount                 = 1
  reset_period           = "MONTHLY"
  display_name           = "always-free-guard"
  description            = "Guard budget for Always Free tenancy — alerts on any spend"
  processing_period_type = "MONTH"

  target_type = "COMPARTMENT"
  targets     = [local.compartment_id]
}

# Alert: actual spend reaches $0.01 (any charge at all)
resource "oci_budget_alert_rule" "any_spend" {
  budget_id      = oci_budget_budget.always_free.id
  display_name   = "any-spend-alert"
  description    = "Alert when any actual charge is detected"
  type           = "ACTUAL"
  threshold      = 1
  threshold_type = "ABSOLUTE"
  recipients     = var.budget_alert_email
  message        = "WARNING: Your Always Free OCI tenancy has incurred a charge. Check the OCI console immediately."
}

# Alert: forecasted spend will exceed $0
resource "oci_budget_alert_rule" "forecast_overspend" {
  budget_id      = oci_budget_budget.always_free.id
  display_name   = "forecast-overspend-alert"
  description    = "Alert when forecasted spend will exceed budget"
  type           = "FORECAST"
  threshold      = 100
  threshold_type = "PERCENTAGE"
  recipients     = var.budget_alert_email
  message        = "WARNING: Forecasted spend will exceed budget. Review your OCI resources for anything outside Always Free limits."
}
