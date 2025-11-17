#!/bin/bash
set -e

# Qualys Registry Sensor - Azure AKS Deployment Script

echo "==================================="
echo "Qualys Registry Sensor - Azure AKS"
echo "==================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v az >/dev/null 2>&1 || { echo "Error: Azure CLI (az) is required but not installed."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: Terraform is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is required but not installed."; exit 1; }

# Check Azure login
echo "Checking Azure authentication..."
az account show >/dev/null 2>&1 || { echo "Error: Not logged into Azure. Run 'az login' first."; exit 1; }

echo "✓ Prerequisites met"
echo ""

# Check for terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo "Error: terraform.tfvars not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and fill in your values."
    exit 1
fi

echo "Step 1: Initializing Terraform..."
terraform init

echo ""
echo "Step 2: Planning infrastructure deployment..."
terraform plan -out=tfplan

echo ""
read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "Step 3: Deploying infrastructure..."
terraform apply tfplan

echo ""
echo "Step 4: Getting AKS credentials..."
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo ""
echo "Step 5: Deploying Qualys DaemonSet..."
# Get the image location from Terraform output
IMAGE_LOCATION=$(terraform output -raw qualys_image_location)

# Update the DaemonSet with the correct image
sed "s|YOUR_REGISTRY/qualys/qcs-sensor:latest|$IMAGE_LOCATION|g" ../kubernetes/qualys-daemonset.yaml | kubectl apply -f -

echo ""
echo "Step 6: Verifying deployment..."
kubectl get daemonset -n qualys-sensor
kubectl get pods -n qualys-sensor

echo ""
echo "==================================="
echo "Deployment Complete!"
echo "==================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""
echo "To check sensor status:"
echo "  kubectl get pods -n qualys-sensor"
echo "  kubectl logs -n qualys-sensor -l app=qualys-container-sensor"
echo ""
echo "To access the cluster:"
echo "  az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
echo ""
