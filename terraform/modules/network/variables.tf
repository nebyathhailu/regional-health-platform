variable "az_count" {
  description = <<-EOT
    Number of distinct-AZ subnets to select for az_diverse_subnet_ids. RDS
    subnet groups and ALBs both require >= 2 Availability Zones on real AWS —
    default matches that floor.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1
    error_message = "az_count must be at least 1."
  }
}
