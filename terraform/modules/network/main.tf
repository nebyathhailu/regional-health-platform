# =============================================================================
# modules/network — shared default-VPC/subnet lookup
#
# Extracted out of modules/data and modules/service, which each independently
# declared the same `data "aws_vpc" "default"` + `data "aws_subnets" "default"`
# lookup and hand-rolled the same "ingress_cidrs defaults to the VPC CIDR"
# pattern. Every AWS module in this repo should source VPC/subnet facts from
# here instead of re-querying them, so there's one place to update if the
# default-VPC assumption ever changes (e.g. to a purpose-built VPC) — and one
# place to fix if the AZ-diversity logic below needs adjusting.
#
# Neither sibling module actually handled AZ diversity: RDS subnet groups and
# ALBs both require subnets across >= 2 distinct Availability Zones on real
# AWS, not just "N subnet ids from the VPC" — the default VPC's subnet id
# order isn't guaranteed AZ-diverse. az_diverse_subnet_ids picks one subnet
# per distinct AZ instead of assuming order, and fails the plan loudly if the
# VPC can't actually satisfy the AZ count requested.
# =============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "detail" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  subnet_azs   = { for id, s in data.aws_subnet.detail : id => s.availability_zone }
  distinct_azs = distinct([for id, az in local.subnet_azs : az])

  # One subnet id per distinct AZ (first match found per AZ — stable given a
  # fixed subnet set, since for-expressions over data.aws_subnet.detail
  # iterate in sorted-key/id order).
  first_subnet_per_az = {
    for az in local.distinct_azs :
    az => [for id, a in local.subnet_azs : id if a == az][0]
  }

  az_diverse_subnet_ids = slice(
    values(local.first_subnet_per_az),
    0,
    min(var.az_count, length(local.first_subnet_per_az))
  )
}

# Fail loudly here, at plan time, if the default VPC can't satisfy the
# AZ-diversity a caller asked for — instead of every consumer separately
# discovering DBSubnetGroupDoesNotCoverEnoughAZs (or the ALB equivalent) at
# apply, with no earlier warning.
check "enough_azs" {
  assert {
    condition     = length(local.az_diverse_subnet_ids) >= var.az_count
    error_message = "Default VPC only has ${length(local.first_subnet_per_az)} distinct AZ(s) with subnets, but az_count=${var.az_count} was requested. RDS subnet groups and ALBs both need >= 2 AZs on real AWS."
  }
}
