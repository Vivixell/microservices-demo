#!/bin/bash
# ──────────────────────────────────────────────
# Online Boutique — Teardown Script
# Destroys all AWS resources in the correct order
# Run from the repo root: bash scripts/teardown.sh
# ──────────────────────────────────────────────

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="online-boutique"

echo "⚠️  This will destroy ALL resources for the Online Boutique project."
echo "    Region: $AWS_REGION"
echo "    Cluster: $CLUSTER_NAME"
echo ""
read -p "Are you sure? Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1 — Delete Kubernetes Ingresses (triggers ALB deletion)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null || true

echo "Deleting all Ingress resources across all namespaces..."
kubectl delete ingress --all --all-namespaces 2>/dev/null || echo "  (kubectl not available or no ingresses found, skipping)"

echo "Waiting 90s for AWS Load Balancer Controller to delete ALBs..."
sleep 90

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2 — Clearing ECR images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
services=(
  frontend cartservice productcatalogservice currencyservice
  paymentservice shippingservice emailservice checkoutservice
  recommendationservice adservice loadgenerator
)

for service in "${services[@]}"; do
  repo="online-boutique/${service}"
  echo "Clearing images from $repo..."
  image_ids=$(aws ecr list-images \
    --repository-name "$repo" \
    --region "$AWS_REGION" \
    --query 'imageIds[*]' \
    --output json 2>/dev/null || echo "[]")

  if [ "$image_ids" != "[]" ] && [ -n "$image_ids" ]; then
    aws ecr batch-delete-image \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --image-ids "$image_ids" > /dev/null
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3 — Terraform destroy: eks-tools"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/eks-tools
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo "Sleeping 60s to allow any remaining LBC-managed resources to clean up..."
sleep 60


echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3b — Terraform destroy: argocd-app"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/argocd-app
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4 — Terraform destroy: ecr"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/ecr
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5 — Terraform destroy: rds"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/rds
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6 — Terraform destroy: eks-cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/eks-cluster
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7 — Terraform destroy: vpc"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "NOTE: If this step fails with DependencyViolation, an orphaned ALB"
echo "still exists. Go to EC2 Console → Load Balancers, delete it and its"
echo "Target Groups manually, then re-run: cd terraform/vpc && terraform destroy -auto-approve"
echo ""
cd terraform/vpc
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 8 — Delete Secrets Manager secrets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
secrets=(
  "online-boutique/sonarqube-db"
  "online-boutique/grafana-admin"
  "online-boutique/grafana-github-oauth"
)

for secret in "${secrets[@]}"; do
  echo "Deleting secret: $secret"
  aws secretsmanager delete-secret \
    --secret-id "$secret" \
    --force-delete-without-recovery \
    --region "$AWS_REGION" 2>/dev/null || echo "  (not found, skipping)"
done

echo ""
echo "✅ Teardown complete."
echo ""
echo "Not deleted (manual cleanup if needed):"
echo "  - S3 state bucket: drimble-statefiles"
echo "  - IAM role: github-actions-online-boutique"
echo "  - ACM certificate"
echo "  - Route53 records"