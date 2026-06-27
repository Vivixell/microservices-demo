#!/bin/bash
# ──────────────────────────────────────────────
# Online Boutique — Teardown Script
# Destroys all AWS resources in the correct order
# Run from the repo root: bash teardown.sh
# ──────────────────────────────────────────────

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="online-boutique"

echo "⚠️  This will destroy ALL resources for the Online Boutique project."
echo "    Region: $AWS_REGION"
echo "    Cluster: $CLUSTER_NAME"
echo ""

if [ "${AUTO_APPROVE:-false}" != "true" ]; then
  read -p "Are you sure? Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Helper: poll until no ALBs matching cluster name remain ──
wait_for_albs_deleted() {
  echo "Polling for ALB deletion (timeout: 10 min)..."
  local deadline=$(( $(date +%s) + 600 ))
  while true; do
    count=$(aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" \
      --query "length(LoadBalancers[?contains(LoadBalancerName, 'online-boutique')])" \
      --output text 2>/dev/null || echo "0")
    if [ "$count" -eq 0 ]; then
      echo "  ✅ All ALBs deleted."
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "  ⚠️  Timeout waiting for ALBs. Check EC2 Console → Load Balancers."
      echo "      Delete remaining ALBs and Target Groups manually, then re-run vpc destroy."
      break
    fi
    echo "  $count ALB(s) still exist — waiting 30s..."
    sleep 30
  done
}

# ── Helper: wait for EKS nodegroups to finish any in-progress operations ──
wait_for_eks_ready() {
  echo "Checking EKS cluster status..."
  local deadline=$(( $(date +%s) + 300 ))
  while true; do
    status=$(aws eks describe-cluster \
      --name "$CLUSTER_NAME" \
      --region "$AWS_REGION" \
      --query "cluster.status" \
      --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$status" = "ACTIVE" ] || [ "$status" = "NOT_FOUND" ]; then
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "  ⚠️  EKS cluster did not reach ACTIVE state in time, proceeding anyway."
      break
    fi
    echo "  Cluster status: $status — waiting 20s..."
    sleep 20
  done
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1 — Delete Kubernetes Ingresses (triggers ALB & DNS deletion)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

wait_for_eks_ready

if aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"; then
  echo "Deleting all Ingress resources across all namespaces..."
  kubectl delete ingress --all --all-namespaces 2>/dev/null || echo "  (no ingresses found)"

  echo "Waiting for AWS Load Balancer Controller to delete ALBs..."
  wait_for_albs_deleted
else
  echo "  ⚠️  Could not connect to cluster — it may already be gone."
  echo "      Checking for orphaned ALBs anyway..."
  wait_for_albs_deleted
fi

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
    echo "  ✅ Cleared $repo"
  else
    echo "  (no images found in $repo, skipping)"
  fi
done


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2b — Remove ArgoCD finalizer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Ensure we are connected to the cluster before patching
if aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null; then
  kubectl patch application online-boutique -n argocd \
    --type json \
    -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null \
    || echo "  (ArgoCD app not found or already removed)"
  
  echo "Waiting 60s to ensure finalizer drops..."
  sleep 60
else
  echo "  (Could not connect to cluster, skipping finalizer removal)"
fi


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3 — Terraform destroy: argocd-app"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/argocd-app
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

# Give ArgoCD time to finish reconciliation teardown before pulling LBC
echo "Waiting 60s for ArgoCD to finish reconciliation teardown..."
sleep 60

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3b — Terraform destroy: eks-tools"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/eks-tools
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

echo "Polling to confirm all LBC-managed resources are gone before proceeding..."
wait_for_albs_deleted

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

# RDS deletion (especially with final snapshot skipped) can take a few minutes
echo "Waiting 120s for RDS instance to fully terminate..."
sleep 120

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6 — Terraform destroy: eks-cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform/eks-cluster
terraform init -reconfigure
terraform destroy -auto-approve
cd ../..

# EKS control plane deletion can take 10–15 min; Terraform waits internally,
# but we add a safety buffer before hitting the VPC
echo "  - Route53 Base Hosted Zone (ExternalDNS successfully removed the subdomains)"
echo "Waiting 180s buffer after EKS cluster destroy before VPC teardown..."
sleep 180

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7 — Terraform destroy: vpc"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "NOTE: If this step fails with DependencyViolation, an orphaned ALB"
echo "still exists. Delete it manually in EC2 Console → Load Balancers,"
echo "then re-run: cd terraform/vpc && terraform destroy -auto-approve"
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
echo "  - S3 Terraform state bucket: drimble-statefiles"
echo "  - IAM role: github-actions-online-boutique"
echo "  - ACM certificate (vicops.xyz)"
