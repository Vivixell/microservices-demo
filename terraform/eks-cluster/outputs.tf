output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "EKS node security group — referenced by RDS to allow port 5432"
  value       = module.eks.node_security_group_id
}

output "aws_lbc_irsa_arn" {
  value = module.aws_lbc_irsa.iam_role_arn
}

output "cluster_autoscaler_irsa_arn" {
  value = module.cluster_autoscaler_irsa.iam_role_arn
}
