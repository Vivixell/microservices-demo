terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
  }

  backend "s3" {
    bucket       = "drimble-statefiles"
    key          = "online-boutique/ecr/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  services = [
    "frontend",
    "cartservice",
    "productcatalogservice",
    "currencyservice",
    "paymentservice",
    "shippingservice",
    "emailservice",
    "checkoutservice",
    "recommendationservice",
    "adservice",
    "loadgenerator",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "online-boutique/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # free AWS-native vulnerability scan on every push
  }

  tags = {
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}

# Keep only last 5 images per repo — avoids unbounded storage cost
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
