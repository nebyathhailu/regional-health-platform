# `modules/data` — RDS MySQL + Secrets Manager

Group-owned platform module. Provisions the managed database each teammate
migrates onto (off the local container from A1) and the Secrets Manager
credential envelope `modules/service` resolves at boot. Service-agnostic:
nothing about a specific service is hardcoded — `db_name`/`db_username`/
`secret_name` are the only service-shaped knobs, and even those default
sensibly.

## What it creates

| Resource | Purpose |
|---|---|
| `random_password.master` | Generates the master password — never a variable, never leaves Terraform except into the secret below |
| `aws_db_subnet_group.this` | Subnet group spanning AZ-diverse subnets (via `modules/network`, not just any N subnets) |
| `aws_security_group.db` | Ingress 3306 (scoped CIDR), egress all |
| `aws_db_instance.this` | RDS MySQL 8.0, gp3, `storage_encrypted = true` |
| `aws_secretsmanager_secret` / `_version` | The credential envelope `modules/service` reads at boot |

VPC/subnet facts (`vpc_id`, `vpc_cidr_block`, `az_diverse_subnet_ids`) come
from [`modules/network`](../network/README.md), not a local data source —
see that module's README for why it exists.

## Inputs

| Name | Default | Notes |
|---|---|---|
| `name_prefix` | `devops-g1-ls` | Name/tag/identifier prefix |
| `db_name` | `capacity_lab` | Application database |
| `db_username` | `app` | Master/app user |
| `instance_class` | `db.t3.micro` | 10k patients (A1 scale) is tiny |
| `allocated_storage` | `20` | RDS-MySQL gp3 minimum |
| `engine_version` | `8.0` | Matches A1 |
| `secret_name` | `regional-health/db` | Secrets Manager name |
| `ingress_cidrs` | default VPC CIDR | **Never `0.0.0.0/0`** — enforced by a `validation` block, not just documentation |
| `skip_final_snapshot` | `true` | Lab default; override to `false` in a real production root |
| `deletion_protection` | `false` | Lab default; override to `true` in a real production root |
| `recovery_window_in_days` | `0` | Lab default (immediate secret purge on delete); override to `7`-`30` in a real production root |

The first six are the frozen contract in [`docs/MODULE-CONTRACTS.md`](../../../docs/MODULE-CONTRACTS.md);
the rest are additive and don't change it. **There is no password input** — see
below.

## Outputs

`db_endpoint`, `db_port`, `secret_arn`, `secret_name` (contract) + `db_instance_id`,
`db_security_group_id`, `db_subnet_group_name` (additive).

## Password handling (C3)

The master password is generated in-module with `random_password` and written
directly into the Secrets Manager secret version. It is **never accepted as a
variable** — there's no input for it — so it can't land in a caller's tfvars,
CLI history, or CI log. The only place it exists outside the secret is
Terraform state, which is why remote state (S3 + DynamoDB lock, per the
assignment's bootstrap) has to stay access-controlled; this module can't make
state itself secret.

Secret envelope JSON keys, exactly (frozen by the contract):
`engine`, `username`, `password`, `host`, `port`, `dbname`. `modules/service`
passes only `secret_arn` + `db_endpoint`/`db_port` into user-data — the app
calls `GetSecretValue` itself at boot. No plaintext credential in git, image,
or logged output.

## LocalStack fidelity caveats (for FIDELITY.md)

- **RDS endpoint hostname is loopback-shaped (`"localhost"`, possibly
  `"127.0.0.1"`) on LocalStack.** From inside another LocalStack-emulated
  container (e.g. the EC2 instance in `modules/service`) that resolves to the
  container itself, not to LocalStack — the same class of bridge-networking
  break `modules/service` calls "break #1". This module rewrites the host to
  `localhost.localstack.cloud` before it ever leaves Terraform (see
  `local.db_host` in `main.tf`), so `db_endpoint` and the secret's `host`
  field are already correct — no caller-side workaround needed. A `check`
  block fails the plan loudly if the rewrite ever still produces a loopback
  host (e.g. a future LocalStack version changes the endpoint format), rather
  than silently handing every consumer an unreachable address. On real AWS,
  `aws_db_instance.address` is never loopback-shaped, so the rewrite is a
  no-op there.
- **Engine substitution.** LocalStack's default RDS emulation can substitute
  MariaDB for a requested `mysql` engine unless the LocalStack container itself
  is started with `RDS_MYSQL_DOCKER=1`. That's a LocalStack startup/env
  concern, not something this module's Terraform controls — set it in
  whatever starts LocalStack (Codespace devcontainer / CI job), or schema
  differences vs. A1's real MySQL 8.0 may surface late.
- **Security group enforcement is unverified on LocalStack RDS**, same caveat
  `modules/service` documents for EC2: `aws_security_group.db` exists for IaC +
  `trivy config`; verify real enforcement against actual AWS with a
  disallowed-source connection attempt.
- **`storage_encrypted = true` is declared, not verified.** LocalStack doesn't
  perform real encryption-at-rest; the flag exists so the Terraform is
  correct/scannable IaC and so the same code is correct unchanged on real AWS.

## Testing

- `tofu fmt` + `tofu validate` clean.
- **Not yet runtime-verified** — needs a LocalStack apply with an auth token to
  confirm: the `localhost` → bridge-alias rewrite is actually reachable from an
  instance built by `modules/service`, `modules/network`'s AZ-diverse subnet
  selection actually satisfies LocalStack's RDS subnet-group requirement, and
  the secret envelope round-trips through a real `GetSecretValue` call from
  the app. Tracking on first `make up`.
