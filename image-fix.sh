# ECR="021104859097.dkr.ecr.us-east-1.amazonaws.com/online-boutique"

# services=(
#   adservice
#   cartservice
#   checkoutservice
#   currencyservice
#   emailservice
#   loadgenerator
#   paymentservice
#   productcatalogservice
#   recommendationservice
#   shippingservice
# )

# for service in "${services[@]}"; do
#   sed -i "s|image: ${service}$|image: ${ECR}/${service}:latest|g" kubernetes-manifests/*.yaml
#   echo "✅ Updated: $service"
# done


# ──────────────────────────────────────────────
# Rename terraform folders and files to match workflow expectations
# ──────────────────────────────────────────────

# Rename folders
# mv "terraform/eks cluster" "terraform/eks-cluster"
# mv "terraform/eks helm" "terraform/eks-tools"

# # Rename files inside eks-cluster
# mv "terraform/eks-cluster/eks-cluster-main.tf" "terraform/eks-cluster/main.tf"
# mv "terraform/eks-cluster/eks-cluster-outputs.tf" "terraform/eks-cluster/outputs.tf"

# # Rename files inside eks-tools
# mv "terraform/eks-tools/eks-tools-main.tf" "terraform/eks-tools/main.tf"

# echo "✅ All folders and files renamed correctly"

mv "terraform/rds/rds-main.tf" "terraform/rds/main.tf"
echo "rds main renamed correctly"
mv "terraform/rds/rds-outputs.tf" "terraform/rds/outputs.tf"
echo "rds outputs renamed correctly"

echo "✅ All folders and files renamed correctly"
