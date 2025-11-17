#!/bin/bash
set -e

# Qualys Registry Sensor - GCP GKE Deployment Script

echo "==================================="
echo "Qualys Registry Sensor - GCP GKE"
echo "==================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v gcloud >/dev/null 2>&1 || { echo "Error: gcloud CLI is required but not installed."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: Terraform is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is required but not installed."; exit 1; }

# Check GCP authentication
echo "Checking GCP authentication..."
gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1 || { echo "Error: Not logged into GCP. Run 'gcloud auth login' first."; exit 1; }

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
echo "Step 4: Getting GKE credentials..."
PROJECT_ID=$(terraform output -raw project_id)
REGION=$(terraform output -raw region)
CLUSTER_NAME=$(terraform output -raw cluster_name)
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

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
echo "Project: $PROJECT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""
echo "To check sensor status:"
echo "  kubectl get pods -n qualys-sensor"
echo "  kubectl logs -n qualys-sensor -l app=qualys-container-sensor"
echo ""
echo "To access the cluster:"
echo "  gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION --project $PROJECT_ID"
echo ""
