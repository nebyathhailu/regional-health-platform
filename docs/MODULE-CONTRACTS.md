# Module contracts

The interface each group module must honour so individual roots and the other
modules compose cleanly. Owners may add inputs, but must not break these.

## `terraform/modules/network` (owner: Rigbe)

Shared default-VPC/subnet lookup — no resources, data sources only. Originally
consumed by `modules/data` for its RDS subnet group; that dependency is gone
now that the database moved to Aiven (2026-08-18, see `modules/data`'s
contract below) — `modules/data` no longer needs a VPC at all. `modules/service`
still needs VPC/subnet facts for its EC2 instance and ALB and should adopt
this module (not yet done, to avoid rewriting that module's already-open PR
out from under it).

**Inputs**

| Name | Default | Notes |
|---|---|---|
| `az_count` | `2` | Distinct AZs to select for `az_diverse_subnet_ids` |

**Outputs**

| Name | Meaning |
|---|---|
| `vpc_id` | Default VPC id |
| `vpc_cidr_block` | Default VPC CIDR — the scoped-ingress fallback |
| `subnet_ids` | All default-VPC subnet ids (not AZ-guaranteed) |
| `az_diverse_subnet_ids` | Up to `az_count` subnet ids, one per distinct AZ |

## `terraform/modules/data` (owner: Rigbe)

> **2026-08-18:** switched from RDS (not on LocalStack's free Hobby tier) to
> Aiven for MySQL — a real external managed MySQL, provisioned by hand, not
> by this module. **Outputs are unchanged.** Inputs below reflect the current
> (Aiven) shape; the RDS-only inputs this table used to list
> (`db_username`, `instance_class`, `allocated_storage`, `engine_version`)
> are gone along with the RDS resources that used them.

**Inputs**

| Name | Default | Notes |
|---|---|---|
| `db_name` | `capacity_lab` | database name on the Aiven service |
| `secret_name` | `regional-health/db` | Secrets Manager name |
| `aiven_host` | — | no default, caller-supplied |
| `aiven_port` | — | no default, caller-supplied |
| `aiven_username` | `avnadmin` | Aiven's free-tier admin username |
| `aiven_password` | — | no default, `sensitive = true`, sourced via `TF_VAR_aiven_password` |

**Outputs** (consumed by `service` + individual roots)

| Name | Meaning |
|---|---|
| `db_endpoint` | DB **host only** (not host:port) |
| `db_port` | DB port |
| `secret_arn` | Secrets Manager ARN of the credential envelope |
| `secret_name` | Secrets Manager name |

Secret envelope JSON keys, exactly: `engine`, `username`, `password`, `host`,
`port`, `dbname`. No plaintext secret in git, image, or logged output.

## `terraform/modules/service` (owner: Nebyat)

**Inputs**

| Name | Default | Notes |
|---|---|---|
| `name_prefix` | — | name/tag prefix |
| `app_ami_id` | — | `localstack-ec2/app:ami-<sha12>` from CI |
| `instance_type` | `t3.small` | |
| `app_port` | `3000` | |
| `secret_arn` | — | from `data.secret_arn` — **value never passed** |
| `db_endpoint` | — | from `data.db_endpoint` (host only) |
| `db_port` | `3306` | from `data.db_port` |
| `app_start_command`, `app_workdir`, `app_env`, `ingress_cidrs` | see module | service-specific knobs |

**Output:** `instance_id` (+ `instance_private_ip`, `app_security_group_id`, `alb_dns_name`).

## Golden CI (`.github/workflows/golden-ci.yml`, owner: Meron)

Reusable workflow. Gate order: `gitleaks` → `trivy config` → `zizmor` →
`docker build` → `trivy image` → tag AMI `localstack-ec2/app:ami-<sha12>` →
`tflocal apply`. Scan jobs run `permissions: contents: read` with **no secrets**.
Every action pinned to a full commit SHA.
