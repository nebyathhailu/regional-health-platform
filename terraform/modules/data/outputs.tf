# Contract outputs (see MODULE-CONTRACTS.md): db_endpoint, db_port, secret_arn,
# secret_name. The rest are additive conveniences for callers/reviewers.

output "db_endpoint" {
  description = "DB host only (not host:port) — already bridge-reachable on LocalStack, see main.tf FIDELITY note."
  value       = local.db_host
}

output "db_port" {
  description = "DB port."
  value       = aws_db_instance.this.port
}

output "secret_arn" {
  description = "Secrets Manager ARN of the credential envelope. Pass this (never the value) to modules/service."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secrets Manager secret name."
  value       = aws_secretsmanager_secret.db.name
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_security_group_id" {
  description = "Security group governing the RDS instance."
  value       = aws_security_group.db.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name."
  value       = aws_db_subnet_group.this.name
}
