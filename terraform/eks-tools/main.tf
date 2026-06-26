terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    } 
  }

  backend "s3" {
    bucket       = "drimble-statefiles"
    key          = "online-boutique/eks-tools/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# ──────────────────────────────────────────────
# Remote state references
# ──────────────────────────────────────────────
data "terraform_remote_state" "eks_cluster" {
  backend = "s3"
  config = {
    bucket = "drimble-statefiles"
    key    = "online-boutique/eks-cluster/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "rds" {
  backend = "s3"
  config = {
    bucket = "drimble-statefiles"
    key    = "online-boutique/rds/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_secretsmanager_secret_version" "sonarqube_db" {
  secret_id = data.terraform_remote_state.rds.outputs.db_secret_arn
}

locals {
  cluster_name = data.terraform_remote_state.eks_cluster.outputs.cluster_name
  db_creds     = jsondecode(data.aws_secretsmanager_secret_version.sonarqube_db.secret_string)
}

# ──────────────────────────────────────────────
# Providers authenticated via EKS
# ──────────────────────────────────────────────
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks_cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks_cluster.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks_cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks_cluster.outputs.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

# ──────────────────────────────────────────────
# Helm Releases
# ──────────────────────────────────────────────
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = local.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.eks_cluster.outputs.aws_lbc_irsa_arn
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "awsRegion"
    value = "us-east-1"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.eks_cluster.outputs.cluster_autoscaler_irsa_arn
  }

  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "2m"
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "7.3.4"
  create_namespace = true
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  version          = "61.3.2"
  create_namespace = true

  values = [
    file("${path.module}/grafana-values.yaml")
  ]

  set {
    name  = "grafana.adminUser"
    value = "admin"
  }

  set {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin.result
  }

}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  version          = "v1.15.1"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "sonarqube" {
  name             = "sonarqube"
  repository       = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart            = "sonarqube"
  namespace        = "sonarqube"
  version          = "10.6.1+2748"
  create_namespace = true

  values = [
    file("${path.module}/sonarqube-values.yaml")
  ]

  set {
    name  = "postgresql.enabled"
    value = "false"
  }

  set {
    name  = "jdbcOverwrite.enable"
    value = "true"
  }

  set {
    name  = "jdbcOverwrite.jdbcUrl"
    value = "jdbc:postgresql://${data.terraform_remote_state.rds.outputs.db_endpoint}/sonar"
  }

  set {
    name  = "jdbcOverwrite.jdbcUsername"
    value = local.db_creds["username"]
  }

  set {
    name  = "jdbcOverwrite.jdbcPassword"
    value = local.db_creds["password"]
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.storageClass"
    value = "gp3"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }
}


# ──────────────────────────────────────────────
# Grafana Admin Password
# ──────────────────────────────────────────────
resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "online-boutique/grafana-admin"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
}

resource "null_resource" "wait_for_argocd" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${local.cluster_name} --region us-east-1
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s
    EOT
  }

  depends_on = [helm_release.argocd]
}


resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "kube-system"
  version          = "1.21.1"

  set {
    name  = "provider.name"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = "us-east-1"
  }

  set {
    name  = "aws.zoneType"
    value = "public"
  }

  set {
    name  = "txtOwnerId"
    value = "online-boutique"   # unique ID so ExternalDNS owns its records
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.eks_cluster.outputs.external_dns_irsa_arn
  }

  set {
    name  = "domainFilters[0]"
    value = "vicops.xyz"
  }

  set {
    name  = "policy"
    value = "sync"   # sync = creates AND deletes records when Ingress is removed
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}