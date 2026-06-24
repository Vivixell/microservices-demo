terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket       = "drimble-statefiles"
    key          = "online-boutique/rds/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# ──────────────────────────────────────────────
# Pull VPC outputs
# ──────────────────────────────────────────────
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "drimble-statefiles"
    key    = "online-boutique/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# ──────────────────────────────────────────────
# Pull EKS outputs (for node security group)
# ──────────────────────────────────────────────
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "drimble-statefiles"
    key    = "online-boutique/eks/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  private_subnets      = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  node_security_group  = data.terraform_remote_state.eks.outputs.node_security_group_id
}

# ──────────────────────────────────────────────
# Generate credentials and store in Secrets Manager
# ──────────────────────────────────────────────
resource "random_password" "sonarqube_db" {
  length  = 24
  special = false # RDS passwords don't allow all special chars
}

resource "aws_secretsmanager_secret" "sonarqube_db" {
  name                    = "online-boutique/sonarqube-db"
  recovery_window_in_days = 0 # Allow immediate deletion for demo teardown

  tags = {
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "sonarqube_db" {
  secret_id = aws_secretsmanager_secret.sonarqube_db.id
  secret_string = jsonencode({
    username = "sonarqube"
    password = random_password.sonarqube_db.result
    dbname   = "sonar"
  })
}

# ──────────────────────────────────────────────
# RDS Subnet Group — private subnets only
# ──────────────────────────────────────────────
resource "aws_db_subnet_group" "sonarqube" {
  name       = "sonarqube-db-subnet-group"
  subnet_ids = local.private_subnets

  tags = {
    Name      = "sonarqube-db-subnet-group"
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}

# ──────────────────────────────────────────────
# Security Group — only EKS nodes can reach RDS on 5432
# ──────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "sonarqube-rds-sg"
  description = "Allow PostgreSQL access from EKS nodes only"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [local.node_security_group]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "sonarqube-rds-sg"
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}

# ──────────────────────────────────────────────
# RDS PostgreSQL Instance
# ──────────────────────────────────────────────
resource "aws_db_instance" "sonarqube" {
  identifier        = "sonarqube-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.medium"
  db_name           = "sonar"
  username          = jsondecode(aws_secretsmanager_secret_version.sonarqube_db.secret_string)["username"]
  password          = jsondecode(aws_secretsmanager_secret_version.sonarqube_db.secret_string)["password"]

  # Storage
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 100 # autoscaling ceiling

  # Network
  db_subnet_group_name   = aws_db_subnet_group.sonarqube.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # stays in private subnet

  # Maintenance
  backup_retention_period = 7
  skip_final_snapshot     = true # fine for demo teardown
  deletion_protection     = false

  tags = {
    Name      = "sonarqube-db"
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}
