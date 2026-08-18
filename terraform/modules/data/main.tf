# =============================================================================
# modules/data — Aiven MySQL (external) + Secrets Manager
#
# Trainer update (2026-08-18): RDS isn't on LocalStack's free Hobby tier, so
# the managed database moved to Aiven for MySQL — a real external managed
# MySQL, provisioned by hand (see the trainer's 5-step setup), not by this
# module. This module's job is narrower than it used to be: take the Aiven
# connection details as inputs and write them into the same Secrets Manager
# credential envelope modules/service already resolves at boot. Nothing about
# modules/service's inputs from this module changes — db_endpoint, db_port,
# secret_arn, secret_name all still mean exactly what they meant before.
#
# What this module used to do and no longer does (see git history for the
# RDS-era version): create an aws_db_instance, an aws_db_subnet_group, an
# aws_security_group for MySQL ingress, or generate a master password with
# random_password. None of that applies to an external service outside the
# VPC that already has its own credentials and its own network boundary —
# modules/network is no longer a dependency of this module either. The
# LocalStack "localhost" RDS-endpoint rewrite this module used to carry is
# gone too: Aiven's host is a real external hostname, never loopback-shaped,
# so there's nothing to rewrite.
#
# TLS: Aiven requires TLS and gives you a CA certificate to verify it. That
# cert is NOT secret (it's a public root cert) — it deliberately does not go
# through Secrets Manager or this module. How modules/service's boot process
# gets it to the app (baked into the AMI, fetched from Aiven's public URL,
# or passed as a plain non-sensitive variable) is an app-boot decision, not
# a data-module one — coordinate with whoever owns modules/service.
# =============================================================================

resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.secret_name })
}

# Envelope keys are frozen by MODULE-CONTRACTS.md: engine, username, password,
# host, port, dbname — unchanged by the Aiven switch. modules/service (and any
# consumer) resolves this at boot via GetSecretValue — the value never appears
# in user-data, an image, or git. aiven_password itself is a sensitive
# variable sourced from a CI secret / local env (TF_VAR_aiven_password), the
# same discipline as LOCALSTACK_AUTH_TOKEN — never a default, never in tfvars.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "mysql"
    username = var.aiven_username
    password = var.aiven_password
    host     = var.aiven_host
    port     = var.aiven_port
    dbname   = var.db_name
  })
}
