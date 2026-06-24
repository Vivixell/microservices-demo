output "db_endpoint" {
  description = "RDS endpoint — referenced by EKS SonarQube helm release"
  value       = aws_db_instance.sonarqube.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN containing db credentials"
  value       = aws_secretsmanager_secret.sonarqube_db.arn
}
