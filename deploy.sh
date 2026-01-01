#!/bin/bash
set -e

check_prerequisites() {
    local cloud=$1
    local missing=()

    if ! command -v terraform &> /dev/null; then
        missing+=("terraform")
    fi

    case $cloud in
        aws)
            if ! command -v aws &> /dev/null; then
                missing+=("aws-cli")
            fi
            ;;
        azure)
            if ! command -v az &> /dev/null; then
                missing+=("azure-cli")
            fi
            if ! command -v kubectl &> /dev/null; then
                missing+=("kubectl")
            fi
            ;;
        gcp)
            if ! command -v gcloud &> /dev/null; then
                missing+=("gcloud-sdk")
            fi
            if ! command -v kubectl &> /dev/null; then
                missing+=("kubectl")
            fi
            ;;
    esac

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing prerequisites: ${missing[*]}"
        exit 1
    fi
}

prompt_credentials() {
    echo ""
    echo "Enter Qualys credentials:"
    echo ""

    read -p "Activation ID: " ACTIVATION_ID
    read -p "Customer ID: " CUSTOMER_ID
    read -p "Pod URL [https://qualysapi.qualys.com]: " POD_URL
    POD_URL=${POD_URL:-https://qualysapi.qualys.com}

    echo ""
}

deploy_aws() {
    echo "Deploying to AWS ECS..."

    check_prerequisites "aws"

    if [ ! -f "aws/terraform.tfvars" ]; then
        cp aws/terraform.tfvars.example aws/terraform.tfvars
    fi

    prompt_credentials

    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}

    read -p "ECR Image URI: " QUALYS_IMAGE
    if [ -z "$QUALYS_IMAGE" ]; then
        echo "Error: ECR Image URI is required"
        exit 1
    fi

    cat > aws/terraform.tfvars << EOF
region = "${AWS_REGION}"

cluster_name = "qualys-registry-cluster"

instance_type    = "c5.large"
min_size         = 1
max_size         = 3
desired_capacity = 2

create_vpc = true

key_name = ""

qualys_image         = "${QUALYS_IMAGE}"
qualys_activation_id = "${ACTIVATION_ID}"
qualys_customer_id   = "${CUSTOMER_ID}"
qualys_pod_url       = "${POD_URL}"

qualys_https_proxy = ""
https_proxy        = ""
EOF

    cd aws
    terraform init
    terraform plan -out=tfplan

    echo ""
    read -p "Apply this plan? (yes/no): " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        terraform apply tfplan
        rm -f tfplan
        echo ""
        echo "AWS deployment complete."
    else
        rm -f tfplan
        echo "Deployment cancelled."
    fi

    cd ..
}

deploy_azure() {
    echo "Deploying to Azure AKS..."

    check_prerequisites "azure"

    if [ ! -f "azure/terraform.tfvars" ]; then
        cp azure/terraform.tfvars.example azure/terraform.tfvars
    fi

    prompt_credentials

    read -p "Azure Region [eastus]: " AZURE_REGION
    AZURE_REGION=${AZURE_REGION:-eastus}

    read -p "Resource Group Name [qualys-registry-sensor-rg]: " RG_NAME
    RG_NAME=${RG_NAME:-qualys-registry-sensor-rg}

    cat > azure/terraform.tfvars << EOF
resource_group_name = "${RG_NAME}"
location            = "${AZURE_REGION}"

cluster_name       = "qualys-registry-cluster"
kubernetes_version = "1.28"

node_count   = 2
node_vm_size = "Standard_D2s_v3"

create_acr = true
acr_name   = ""

qualys_activation_id = "${ACTIVATION_ID}"
qualys_customer_id   = "${CUSTOMER_ID}"
qualys_pod_url       = "${POD_URL}"
EOF

    sed -i.bak "s/YOUR_ACTIVATION_ID/${ACTIVATION_ID}/g" kubernetes/qualys-daemonset.yaml
    sed -i.bak "s/YOUR_CUSTOMER_ID/${CUSTOMER_ID}/g" kubernetes/qualys-daemonset.yaml
    sed -i.bak "s|https://your-qualys-platform.qualys.com|${POD_URL}|g" kubernetes/qualys-daemonset.yaml
    rm -f kubernetes/qualys-daemonset.yaml.bak

    cd azure
    terraform init
    terraform plan -out=tfplan

    echo ""
    read -p "Apply this plan? (yes/no): " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        terraform apply tfplan
        rm -f tfplan

        echo "Configuring kubectl..."
        $(terraform output -raw get_credentials_command)

        echo "Deploying Kubernetes resources..."
        cd ..
        kubectl apply -f kubernetes/qualys-daemonset.yaml

        echo "Waiting for pods..."
        kubectl wait --for=condition=ready pod -l app=qualys-container-sensor -n qualys-sensor --timeout=300s || true

        echo ""
        echo "Azure deployment complete."
        echo ""
        kubectl get pods -n qualys-sensor
    else
        rm -f tfplan
        cd ..
        echo "Deployment cancelled."
    fi
}

deploy_gcp() {
    echo "Deploying to GCP GKE..."

    check_prerequisites "gcp"

    if [ ! -f "gcp/terraform.tfvars" ]; then
        cp gcp/terraform.tfvars.example gcp/terraform.tfvars
    fi

    prompt_credentials

    read -p "GCP Project ID: " PROJECT_ID
    if [ -z "$PROJECT_ID" ]; then
        echo "Error: GCP Project ID is required"
        exit 1
    fi

    read -p "GCP Region [us-central1]: " GCP_REGION
    GCP_REGION=${GCP_REGION:-us-central1}

    cat > gcp/terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region     = "${GCP_REGION}"

cluster_name       = "qualys-registry-cluster"
kubernetes_version = "1.28"

network_name = "qualys-registry-network"
subnet_name  = "qualys-registry-subnet"
subnet_cidr  = "10.0.0.0/20"

node_count   = 1
machine_type = "e2-standard-2"

create_gcr = true

qualys_activation_id = "${ACTIVATION_ID}"
qualys_customer_id   = "${CUSTOMER_ID}"
qualys_pod_url       = "${POD_URL}"
EOF

    sed -i.bak "s/YOUR_ACTIVATION_ID/${ACTIVATION_ID}/g" kubernetes/qualys-daemonset.yaml
    sed -i.bak "s/YOUR_CUSTOMER_ID/${CUSTOMER_ID}/g" kubernetes/qualys-daemonset.yaml
    sed -i.bak "s|https://your-qualys-platform.qualys.com|${POD_URL}|g" kubernetes/qualys-daemonset.yaml
    rm -f kubernetes/qualys-daemonset.yaml.bak

    cd gcp
    terraform init
    terraform plan -out=tfplan

    echo ""
    read -p "Apply this plan? (yes/no): " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        terraform apply tfplan
        rm -f tfplan

        echo "Configuring kubectl..."
        $(terraform output -raw get_credentials_command)

        echo "Deploying Kubernetes resources..."
        cd ..
        kubectl apply -f kubernetes/qualys-daemonset.yaml

        echo "Waiting for pods..."
        kubectl wait --for=condition=ready pod -l app=qualys-container-sensor -n qualys-sensor --timeout=300s || true

        echo ""
        echo "GCP deployment complete."
        echo ""
        kubectl get pods -n qualys-sensor
    else
        rm -f tfplan
        cd ..
        echo "Deployment cancelled."
    fi
}

echo ""
echo "Qualys Container Security Registry Sensor - Deployment"
echo ""

if [ -n "$1" ]; then
    CLOUD=$1
else
    echo "Select cloud provider:"
    echo ""
    echo "  1) AWS (ECS)"
    echo "  2) Azure (AKS)"
    echo "  3) GCP (GKE)"
    echo ""
    read -p "Enter choice [1-3]: " CHOICE

    case $CHOICE in
        1) CLOUD="aws" ;;
        2) CLOUD="azure" ;;
        3) CLOUD="gcp" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

case $CLOUD in
    aws)
        deploy_aws
        ;;
    azure)
        deploy_azure
        ;;
    gcp)
        deploy_gcp
        ;;
    *)
        echo "Unknown cloud: $CLOUD"
        echo "Usage: $0 [aws|azure|gcp]"
        exit 1
        ;;
esac
