# =============================================================================
# modules/data — inputs
#
# Service-agnostic: RDS MySQL + Secrets Manager for whichever service consumes
# this module. The master password is generated in-module (random_password) and
# never accepted as a variable — it must never touch a caller's tfvars, CLI arg,
# or CI log. See MODULE-CONTRACTS.md for the frozen input/output contract; the
# extras below (name_prefix, tags, ingress_cidrs, skip_final_snapshot,
# deletion_protection) are additive and don't change it.
# =============================================================================

variable "name_prefix" {
  description = "Prefix for names/tags/identifiers this module creates."
  type        = string
  default     = "devops-g1-ls"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric/hyphens, start with a letter, and not end with a hyphen."
  }
}

variable "tags" {
  description = "Tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# --- Contract inputs (do not remove/rename — see MODULE-CONTRACTS.md) ---------

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "capacity_lab"
}

variable "db_username" {
  description = "Master/app DB username."
  type        = string
  default     = "app"

  validation {
    # MySQL master username: starts with a letter, alnum, <=16 chars, no reserved word.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,15}$", var.db_username)) && !contains(["admin", "rdsadmin", "root"], lower(var.db_username))
    error_message = "db_username must start with a letter, be <=16 alphanumeric characters, and not be a reserved word (admin/rdsadmin/root)."
  }
}

variable "instance_class" {
  description = "RDS instance class. db.t3.micro is plenty for 10k patients (A1 scale)."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must be a valid RDS class, e.g. db.t3.micro."
  }
}

variable "allocated_storage" {
  description = "Allocated storage in GiB. 20 is the RDS-MySQL gp3 minimum."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be >= 20 GiB (RDS-MySQL gp3 minimum)."
  }
}

variable "engine_version" {
  description = "MySQL engine version. Must be the 8.0 line to match A1."
  type        = string
  default     = "8.0"

  validation {
    condition     = can(regex("^8\\.0", var.engine_version))
    error_message = "engine_version must be on the 8.0 line to match A1's MySQL version."
  }
}

variable "secret_name" {
  description = "Secrets Manager secret name holding the credential envelope."
  type        = string
  default     = "regional-health/db"
}

# --- Additive inputs ------------------------------------------------------

variable "ingress_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach MySQL (3306). Default scopes to the default VPC's
    CIDR — NEVER 0.0.0.0/0. Mirrors modules/service's ingress_cidrs convention;
    `trivy config` flags an open ingress here the same way it does there.
  EOT
  type        = list(string)
  default     = null

  validation {
    condition     = var.ingress_cidrs == null ? true : !contains(var.ingress_cidrs, "0.0.0.0/0")
    error_message = "ingress_cidrs must never include 0.0.0.0/0 — MySQL must not be open to the internet. Scope to the VPC CIDR or a narrower range."
  }
}

variable "skip_final_snapshot" {
  description = <<-EOT
    Skip the final snapshot on destroy. Defaults true for lab reproducibility
    (every CI run destroys/recreates against a fresh LocalStack) — a real
    production root should override this to false.
  EOT
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = <<-EOT
    RDS deletion protection. Defaults false so `tofu destroy` and repeated CI
    runs don't get stuck — a real production root should override this to true.
  EOT
  type        = bool
  default     = false
}

variable "recovery_window_in_days" {
  description = <<-EOT
    Secrets Manager recovery window (days) before a deleted secret is purged
    for good. Defaults to 0 so a destroy/apply cycle against a persistent
    LocalStack container can reuse the same secret_name immediately — a real
    production root should override this to a non-zero value (AWS allows
    7-30) for an actual recovery grace period.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (immediate deletion — LocalStack/lab default) or between 7 and 30 (AWS's allowed range)."
  }
}
