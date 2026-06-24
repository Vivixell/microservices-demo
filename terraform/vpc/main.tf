terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9"
    }
  }

  backend "s3" {
    bucket       = "drimble-statefiles"
    key          = "online-boutique/vpc/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # native S3 locking, no DynamoDB needed
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "online-boutique-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # Disable module's NAT — we're using regional NAT below
  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Project     = "online-boutique"
    ManagedBy   = "terraform"
    Environment = "demo"
  }
}


resource "aws_nat_gateway" "regional" {
  # The correct argument for Regional NAT
  availability_mode = "regional" 
  
  connectivity_type = "public"
  
  # Attach directly to the VPC, NOT a subnet
  vpc_id            = module.vpc.vpc_id 

  tags = {
    Name = "online-boutique-regional-nat"
  }
}

# Point all private subnets to the regional NAT
resource "aws_route" "private_nat" {
  count = length(module.vpc.private_route_table_ids)

  route_table_id         = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.regional.id
}