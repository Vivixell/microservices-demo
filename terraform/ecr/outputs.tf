output "repository_urls" {
  description = "Map of service name to ECR repository URL — used in GitHub Actions build-push workflow"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "registry_id" {
  description = "AWS account ID — used for docker login in GitHub Actions"
  # Directly reference one of the keys in your map to grab the shared account ID
  value       = aws_ecr_repository.services["frontend"].registry_id
}