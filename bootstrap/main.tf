# =============================================================================
# bootstrap — Terraform remote state store (S3 + DynamoDB lock table)
#
# Run ONCE, by hand, before any individual repo's root module can `tofu init`
# with a real backend. This is deliberately its own root, not a module other
# code sources: it has no backend of its own (its own state is local, on
# purpose -- bootstrapping the state store can't depend on the state store
# existing yet), and it's the one piece of this lab you genuinely run only
# once, not on every CI apply.
#
# Each individual repo points its own `backend "s3" {}` block at this bucket
# via `-backend-config`, using a distinct `key` per person so state files
# don't collide:
#
#   tflocal init \
#     -backend-config="bucket=${var.name_prefix}-tfstate" \
#     -backend-config="key=<your-repo-name>/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=${var.name_prefix}-tflock"
#
# C1 (ASSIGNMENT.md): "Remote state on S3 + DynamoDB lock (the bootstrap
# script is provided — you don't write it)." This is that script.
# =============================================================================

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# No provider "aws" block: tflocal injects LocalStack endpoints/credentials
# automatically (see terraform/versions.tf in each individual repo for the
# same reasoning) — only region needs setting explicitly, and the aws
# provider's default region behavior + tflocal's override handle that.

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.name_prefix}-tfstate"

  tags = merge(var.tags, { Name = "${var.name_prefix}-tfstate" })
}

# Versioning: a bad `apply` can corrupt state; versioning means the previous
# good state is recoverable instead of gone. Cheap insurance, standard
# practice for any Terraform remote state bucket.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access -- state files can contain sensitive values
# (ASSIGNMENT.md C3: "the state file as a credential store"). Never public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lock table: prevents two concurrent `apply`s (e.g. a person and CI, or two
# people) from racing on the same state file. hash_key must be named
# "LockID" -- Terraform's S3 backend requires that exact attribute name.
resource "aws_dynamodb_table" "tflock" {
  name         = "${var.name_prefix}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tflock" })
}
