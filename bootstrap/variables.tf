variable "name_prefix" {
  description = "Prefix for the state bucket and lock table names. Matches the devops-g1-ls convention used elsewhere in this repo."
  type        = string
  default     = "devops-g1-ls"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric/hyphens, start with a letter, and not end with a hyphen."
  }
}

variable "tags" {
  description = "Tags merged onto every resource this bootstrap creates."
  type        = map(string)
  default     = {}
}
