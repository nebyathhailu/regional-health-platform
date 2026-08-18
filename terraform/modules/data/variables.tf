# =============================================================================
# modules/data — inputs
#
# Service-agnostic: writes Aiven MySQL connection details into the shared
# Secrets Manager envelope for whichever service consumes this module. See
# MODULE-CONTRACTS.md for the frozen output contract (unchanged by the Aiven
# switch); the aiven_* inputs replace what used to be RDS-provisioning inputs.
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
  description = "Application database name on the Aiven service (create it yourself on the Aiven console/CLI, or use their defaultdb)."
  type        = string
  default     = "capacity_lab"

  validation {
    # Standard MySQL identifier rules: letters, digits, underscore; starts
    # with a letter or underscore; <=64 chars. (Not RDS's stricter historical
    # DBName-parameter constraint — that applied to RDS creating the database
    # itself; here we're just recording the name of a database that already
    # exists on Aiven, created through Aiven's own tooling, so plain MySQL
    # identifier rules are the right check. The default "capacity_lab" itself
    # has an underscore, which is exactly why the old alphanumeric-only regex
    # was wrong.)
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must start with a letter or underscore and be <=64 letters/digits/underscores (MySQL identifier rules)."
  }
}

variable "secret_name" {
  description = "Secrets Manager secret name holding the credential envelope."
  type        = string
  default     = "regional-health/db"
}

# --- Aiven connection details ---------------------------------------------
# All four come from your Aiven service's "Connection details" page. None of
# them belong in a default, a committed tfvars file, or CI log — aiven_host/
# aiven_port/aiven_username are non-secret shape-wise but still describe a
# private service; aiven_password is the one that actually matters to
# gitleaks. Source all four the same way LOCALSTACK_AUTH_TOKEN already is:
# TF_VAR_* env vars fed from a GitHub Actions repo secret / your local shell.

variable "aiven_host" {
  description = "Aiven MySQL service hostname, e.g. mysql-xxxx-yourproject.a.aivencloud.com. No default — always caller-supplied."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.aiven_host))
    error_message = "aiven_host must be a bare hostname (letters, digits, dots, hyphens) — no scheme, no port, no path."
  }
}

variable "aiven_port" {
  description = "Aiven MySQL service port, from the same connection-details page. Aiven assigns this per-service — there's no fixed default like 3306."
  type        = number

  validation {
    condition     = var.aiven_port > 0 && var.aiven_port <= 65535
    error_message = "aiven_port must be a valid TCP port (1-65535)."
  }
}

variable "aiven_username" {
  description = "Aiven MySQL admin username. Aiven's free-tier services all use avnadmin."
  type        = string
  default     = "avnadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,31}$", var.aiven_username))
    error_message = "aiven_username must start with a letter and be <=32 alphanumeric/underscore characters."
  }
}

variable "aiven_password" {
  description = <<-EOT
    Aiven MySQL admin password, from the same connection-details page. No
    default — must be supplied via TF_VAR_aiven_password (CI secret / local
    env), never a tfvars file. This is the one field in this module that
    gitleaks should actually catch if it ever lands in git.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.aiven_password) > 0
    error_message = "aiven_password must not be empty."
  }
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
