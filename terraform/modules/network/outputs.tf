output "vpc_id" {
  description = "Default VPC id."
  value       = data.aws_vpc.default.id
}

output "vpc_cidr_block" {
  description = "Default VPC CIDR block — the scoped-ingress default every module should fall back to instead of 0.0.0.0/0."
  value       = data.aws_vpc.default.cidr_block
}

output "subnet_ids" {
  description = "All subnet ids in the default VPC. Order is not guaranteed AZ-diverse — use az_diverse_subnet_ids for anything that requires AZ spread."
  value       = data.aws_subnets.default.ids
}

output "az_diverse_subnet_ids" {
  description = "Up to az_count subnet ids, one per distinct Availability Zone. Use this (not subnet_ids) for RDS subnet groups, ALBs, or anything else that requires AZ diversity."
  value       = local.az_diverse_subnet_ids
}
