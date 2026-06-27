# Online Boutique — DevSecOps on AWS EKS

![Image description](https://dev-to-uploads.s3.us-east-2.amazonaws.com/uploads/articles/4qrmsk366h1wss7qtiml.png)

A fork of [Google's Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) replatformed onto AWS EKS with a full DevSecOps pipeline — infrastructure as code, GitOps delivery, security scanning, observability, and automated DNS.

---

## Stack

**Infrastructure**
- Terraform: all AWS resources, modular and applied in dependency order via CI
- AWS EKS (Kubernetes 1.32): t3.large nodes with Cluster Autoscaler
- AWS RDS PostgreSQL: backing store for SonarQube
- AWS ALB: single load balancer shared across all three ingresses via ingress groups
- AWS ECR: private container registry for all 11 services

**CI/CD & GitOps**
- GitHub Actions: two pipelines: infrastructure (`terraform.yml`) and build (`build.yml`)
- ArgoCD: GitOps controller, syncs `kubernetes-manifests/` to the cluster on every image tag commit

**Security**
- Gitleaks: secret scanning on every push
- SonarQube: static code analysis with Quality Gate enforcement
- Trivy: container image vulnerability scanning before ECR push
- ACM + cert-manager: TLS termination at the ALB

**Observability**
- Prometheus + Grafana: cluster and application metrics

**DNS**
- ExternalDNS: watches Ingress objects and automatically creates Route 53 records when the ALB is provisioned. No manual DNS steps.

---

## How it works

```
Push to main (src/)
      │
      ▼
GitHub Actions (build.yml)
  ├── Gitleaks        secret scan
  ├── SonarQube       code quality gate
  ├── Docker build    only changed services
  ├── Trivy           image CVE scan
  └── ECR push + commit updated image tags
                      │
                      ▼
                  ArgoCD detects commit
                      │
                      ▼
                  EKS cluster synced
```

Infrastructure is applied once via `terraform.yml` in five stages:

```
vpc → eks-cluster + ecr (parallel) → rds → eks-tools → argocd-app
```

---

## Deployment guide

Full step-by-step setup including prerequisites, AWS bootstrap, and configuration:

👉 **[Read the full guide on dev.to](https://dev.to/ovrobin/building-a-devsecops-pipeline-on-aws-eks-with-terraform-argocd-and-github-actions-5fi4)** 

---

## Repo structure

```
## Repo structure

├── bootstrap/                # S3 state bucket (apply locally, one-time)
├── terraform/
│   ├── vpc/
│   ├── eks-cluster/
│   ├── eks-tools/            # LBC, ExternalDNS, ArgoCD, Grafana, SonarQube
│   ├── rds/
│   ├── ecr/
│   └── argocd-app/
├── kubernetes-manifests/     # All K8s objects — ArgoCD watches this
├── src/                      # Source code for all 11 microservices
├── teardown.sh               # Destroys all AWS resources (can be run locally, but use the teardown workflow)
└── .github/workflows/
    ├── terraform.yml         # Infrastructure pipeline
    ├── build.yml             # Build, scan and push pipeline
    └── teardown.yml          # Manual-only — triggers full teardown
```
