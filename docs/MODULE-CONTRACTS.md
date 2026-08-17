# Module contracts

The interface each group module must honour so individual roots and the other
modules compose cleanly. Owners may add inputs, but must not break these.

## `terraform/modules/network` (owner: Rigbe)

Shared default-VPC/subnet lookup — no resources, data sources only. Consumed
by `modules/data`; `modules/service` should adopt it too (not yet done, to
avoid rewriting that module's already-open PR out from under it).

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

**Inputs**

| Name | Default | Notes |
|---|---|---|
| `db_name` | `capacity_lab` | application database |
| `db_username` | `app` | master/app user |
| `instance_class` | `db.t3.micro` | 10k patients is tiny |
| `allocated_storage` | `20` | RDS-MySQL minimum, gp3 |
| `engine_version` | `8.0` | matches A1 |
| `secret_name` | `regional-health/db` | Secrets Manager name |

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
