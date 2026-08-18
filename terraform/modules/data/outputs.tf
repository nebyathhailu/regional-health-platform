# Contract outputs (see MODULE-CONTRACTS.md): db_endpoint, db_port, secret_arn,
# secret_name — unchanged in meaning by the Aiven switch.

output "db_endpoint" {
  description = "DB host only (not host:port) — the Aiven service hostname, passed straight through (no LocalStack rewrite needed; Aiven is a real external host)."
  value       = var.aiven_host
}

output "db_port" {
  description = "DB port."
  value       = var.aiven_port
}

output "secret_arn" {
  description = "Secrets Manager ARN of the credential envelope. Pass this (never the value) to modules/service."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secrets Manager secret name."
  value       = aws_secretsmanager_secret.db.name
}
