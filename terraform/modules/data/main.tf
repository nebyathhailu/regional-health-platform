# =============================================================================
# modules/data — RDS MySQL + Secrets Manager
#
# Generates the master password in-module (random_password) and writes it
# straight into a Secrets Manager secret version — the value is never a
# variable, so it can't land in a caller's tfvars, CLI history, or CI log. The
# app resolves it from Secrets Manager at boot (see modules/service); this
# module never hands the password to anything but the secret itself.
#
# FIDELITY (LocalStack): RDS returns the literal hostname "localhost" as its
# endpoint. From inside another LocalStack-emulated container (e.g. the EC2
# instance in modules/service) that resolves to the container itself, not to
# LocalStack — the same bridge-networking break modules/service documents as
# "break #1" for db_endpoint. This module rewrites the host to the
# bridge-reachable alias before it ever leaves Terraform, so both the
# `db_endpoint` output and the secret's `host` field are already correct —
# callers don't have to know about the rewrite. See README.md for the rest of
# the fidelity caveats (engine substitution, SG enforcement).
#
# VPC/subnet facts come from modules/network, not a local data source — see
# that module's README for why (dedupes the same lookup modules/service also
# needs, and picks AZ-diverse subnets for the DB subnet group instead of
# assuming order).
# =============================================================================

module "network" {
  source   = "../network"
  az_count = 2
}

locals {
  # Scope ingress to the VPC CIDR unless the caller overrides. Never 0.0.0.0/0.
  ingress_cidrs = var.ingress_cidrs != null ? var.ingress_cidrs : [module.network.vpc_cidr_block]

  # LocalStack hands back a loopback-shaped address for the RDS endpoint
  # ("localhost", possibly "127.0.0.1"), which only resolves to itself from
  # inside another emulated container. Rewrite to the bridge alias so every
  # consumer of this module's outputs gets a host that's actually reachable —
  # real AWS never returns a loopback address here, so this is a no-op there.
  # Strip a possible :port suffix before comparing, in case a future
  # LocalStack version includes one.
  raw_host      = aws_db_instance.this.address
  raw_host_only = split(":", local.raw_host)[0]
  is_loopback   = contains(["localhost", "127.0.0.1", "0.0.0.0"], local.raw_host_only)
  db_host       = local.is_loopback ? "localhost.localstack.cloud" : local.raw_host
}

# Fail loudly, at this module, if the rewrite above still produced a loopback
# host — better than every consumer independently discovering "unreachable
# DB" at boot. If this ever fires, LocalStack's RDS endpoint format changed
# and the match above (raw_host_only) needs updating.
check "db_host_not_loopback" {
  assert {
    condition     = !contains(["localhost", "127.0.0.1", "0.0.0.0"], local.db_host)
    error_message = "db_host resolved to a loopback address after the LocalStack rewrite — modules/service would get an endpoint unreachable from another instance. LocalStack's RDS endpoint format may have changed; update the rewrite in main.tf."
  }
}

# --- Master password ---------------------------------------------------------
# Generated here, never accepted as a variable. Excludes '/', '@', '"', and
# space — all disallowed in an RDS MySQL master password.
resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# --- Networking ----------------------------------------------------------------
# AZ-diverse subnets, not "all default-VPC subnets" — RDS requires the subnet
# group to span >= 2 distinct AZs, which module.network.az_diverse_subnet_ids
# actually guarantees instead of assuming default-VPC subnet order.
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = module.network.az_diverse_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnets" })
}

# Ingress is scoped (see local.ingress_cidrs). Flipping this to 0.0.0.0/0 is the
# same class of deliberate insecure change modules/service documents for
# `trivy config` — don't use this SG as your own red-PR without checking with
# whoever already claimed the ingress-scope break.
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "MySQL (3306) for the ${var.name_prefix} RDS instance"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "MySQL from the app tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = local.ingress_cidrs
  }

  egress {
    description = "all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-sg" })
}

# --- RDS instance --------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  # Declared for IaC hygiene / trivy config; LocalStack doesn't enforce actual
  # encryption-at-rest the way real AWS does.
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.master.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az                = false
  backup_retention_period = 0

  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  tags = merge(var.tags, { Name = "${var.name_prefix}-db" })
}

# --- Secrets Manager -------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.secret_name })
}

# Envelope keys are frozen by MODULE-CONTRACTS.md: engine, username, password,
# host, port, dbname. modules/service (and any consumer) resolves this at boot
# via GetSecretValue — the value never appears in user-data, an image, or git.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "mysql"
    username = var.db_username
    password = random_password.master.result
    host     = local.db_host
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  })
}
