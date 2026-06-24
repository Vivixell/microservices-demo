output "vpc_id" {
  description = "VPC ID — referenced by EKS module"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes go here"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs — ALB and NAT GW"
  value       = module.vpc.public_subnets
}
