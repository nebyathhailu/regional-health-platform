# `modules/network` — shared default-VPC/subnet lookup

Group-owned platform module. Extracted from `modules/data` and
`modules/service`, which had each independently declared the same
`data "aws_vpc" "default"` + `data "aws_subnets" "default"` lookup and the
same "ingress_cidrs defaults to the VPC CIDR" pattern. Every AWS module in
this repo should consume VPC/subnet facts from here rather than re-querying
them.

## What it creates

Nothing — this module is data sources only, no resources. It's a lookup +
derivation layer, not infrastructure.

## Why it exists

Two problems review turned up in `modules/data` and `modules/service`
independently re-implementing the same lookup:

1. **Duplication**: the exact same 10-line VPC/subnet data-source block in
   two files means a change to the VPC-discovery strategy (e.g. moving off
   the default VPC to a purpose-built one) has to be made twice and kept in
   sync by hand.
2. **AZ diversity was silently assumed, not enforced**: RDS subnet groups and
   ALBs both require subnets across >= 2 distinct Availability Zones on real
   AWS. Grabbing `data.aws_subnets.default.ids` (or a naive `slice(ids, 0, 2)`
   of it) doesn't guarantee that — the default VPC's subnet id order isn't
   AZ-ordered. A VPC with subnets skewed toward one AZ would pass `tofu plan`
   and only fail at `apply` with `DBSubnetGroupDoesNotCoverEnoughAZs` (or the
   ALB equivalent), with no earlier signal.

## Inputs

| Name | Default | Notes |
|---|---|---|
| `az_count` | `2` | Distinct AZs to select for `az_diverse_subnet_ids`. 2 matches the RDS subnet group / ALB floor. |

## Outputs

| Name | Meaning |
|---|---|
| `vpc_id` | Default VPC id |
| `vpc_cidr_block` | Default VPC CIDR — the scoped-ingress fallback every module's `ingress_cidrs` default should use instead of `0.0.0.0/0` |
| `subnet_ids` | All subnet ids in the default VPC (order not AZ-guaranteed) |
| `az_diverse_subnet_ids` | Up to `az_count` subnet ids, one per distinct AZ — use this for anything requiring AZ spread |

A `check` block fails the plan loudly if the default VPC can't actually
satisfy the AZ count requested, rather than deferring to an opaque apply-time
AWS error.

## Consumers

- `modules/data` — **no longer a consumer.** It used `vpc_id`/`vpc_cidr_block`/
  `az_diverse_subnet_ids` for its RDS subnet group and security group; both
  are gone now that the database moved to Aiven (2026-08-18), an external
  service outside the VPC entirely. See `modules/data`'s README/`main.tf` for
  the full context.
- `modules/service` — not yet wired up (this module landed after
  `modules/service`'s PR was already open). Still the intended primary
  consumer — its EC2 instance and ALB both need VPC/subnet facts. Adopting it
  there is a follow-up to coordinate with whoever owns that module, so its
  still-open PR isn't rewritten out from under it.

## Testing

- `tofu fmt` + `tofu validate` clean.
- Not yet runtime-verified against LocalStack — same open item as
  `modules/data`, tracked on first `make up`.
