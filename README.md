# Qualys Registry Sensor - Multi-Cloud Deployment

Deploy Qualys Container Registry Sensor across AWS, Azure, and GCP with Terraform.

## Overview

Terraform configurations for deploying Qualys Container Registry Sensor on:
- **AWS ECS**: EC2-based ECS cluster with optional VPC creation
- **Azure AKS**: Managed Kubernetes with Azure Container Registry
- **GCP GKE**: Managed Kubernetes with Google Container Registry

---

## AWS ECS Deployment

Terraform configuration for ECS cluster on EC2 instances with optional VPC creation.

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Private ECR repository with Qualys container image

### Configuration

Edit `aws/terraform.tfvars`:

```hcl
region           = "us-east-1"
cluster_name     = "qualys-registry-cluster"
instance_type    = "c5.large"
desired_capacity = 2

create_vpc = false
vpc_id     = "vpc-xxxxx"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

qualys_image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest"
qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"
```

### Deploy

```bash
cd aws
terraform init
terraform plan
terraform apply
```

### Architecture

**With create_vpc=true**:
- VPC: 172.20.250.0/24
- 2x Public subnets with NAT gateways
- 2x Private subnets for ECS instances
- Auto-scaling group with EC2 instances
- One Qualys sensor task per instance

**With create_vpc=false**:
- Uses existing VPC and subnets
- Requires NAT gateway or internet access for ECR

### Outputs

```bash
terraform output cluster_name
terraform output cluster_arn
terraform output task_definition_arn
```

---

## Azure AKS Deployment

Terraform configuration for AKS cluster with managed node pools and optional ACR.

### Prerequisites

- Azure CLI configured with valid subscription
- Terraform >= 1.0
- kubectl

### Configuration

Edit `azure/terraform.tfvars`:

```hcl
resource_group_name = "qualys-registry-sensor-rg"
location            = "eastus"
cluster_name        = "qualys-registry-cluster"
node_count          = 2
node_vm_size        = "Standard_D2s_v3"

create_acr = true

qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"
```

### Deploy

```bash
cd azure
terraform init
terraform plan
terraform apply
```

### Configure kubectl

```bash
az aks get-credentials \
  --resource-group qualys-registry-sensor-rg \
  --name qualys-registry-cluster
```

### Deploy Sensor DaemonSet

Update image in `kubernetes/qualys-daemonset.yaml` with your ACR location, then:

```bash
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
kubectl get pods -n qualys-sensor
```

### Architecture

- AKS cluster with auto-scaling node pools (1-10 nodes)
- VNet: 10.1.0.0/16 with dedicated subnet
- Azure Container Registry for Qualys images
- Log Analytics workspace for monitoring
- DaemonSet deployment (one pod per node)

### Outputs

```bash
terraform output aks_cluster_name
terraform output acr_login_server
terraform output get_credentials_command
```

---

## GCP GKE Deployment

Terraform configuration for GKE regional cluster with multi-zone node pools.

### Prerequisites

- Google Cloud SDK configured with valid project
- Terraform >= 1.0
- kubectl

### Configuration

Edit `gcp/terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"

cluster_name = "qualys-registry-cluster"
node_count   = 1
machine_type = "e2-standard-2"

create_gcr = true

qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"
```

### Authenticate

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### Deploy

```bash
cd gcp
terraform init
terraform plan
terraform apply
```

### Configure kubectl

```bash
gcloud container clusters get-credentials qualys-registry-cluster \
  --region us-central1 \
  --project YOUR_PROJECT_ID
```

### Deploy Sensor DaemonSet

Update image in `kubernetes/qualys-daemonset.yaml` with your GCR location, then:

```bash
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
kubectl get pods -n qualys-sensor
```

### Architecture

- Regional GKE cluster with multi-zone node pools
- Custom VPC with dedicated subnet ranges
- Google Container Registry for Qualys images
- Cloud Monitoring and Logging integration
- Workload Identity enabled
- DaemonSet deployment (one pod per node)

### Outputs

```bash
terraform output cluster_name
terraform output cluster_endpoint
terraform output get_credentials_command
```

---

## Common Operations

### View Sensor Logs

```bash
kubectl get pods -n qualys-sensor
kubectl logs -n qualys-sensor -l app=qualys-container-sensor --tail=100
kubectl logs -n qualys-sensor <pod-name> -f
```

### Update Sensor Image

```bash
kubectl set image daemonset/qualys-container-sensor \
  qualys-container-sensor=<new-image> \
  -n qualys-sensor
```

### Verify DaemonSet

```bash
kubectl describe daemonset qualys-container-sensor -n qualys-sensor
kubectl get secret qualys-credentials -n qualys-sensor
```

---

## Security Considerations

**Credentials**:
- Store Qualys credentials securely (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)
- Never commit credentials to version control
- Rotate credentials regularly

**Network**:
- Sensors require outbound internet access to Qualys platform
- Use private subnets with NAT gateway
- Configure appropriate security groups and firewall rules

**Permissions**:
- Sensors require elevated capabilities for container scanning
- Review required permissions before deployment
- Follow principle of least privilege

**Images**:
- Store Qualys sensor images in private registries
- Keep sensor images updated
- Scan images for vulnerabilities

---

## Cleanup

### AWS
```bash
cd aws
terraform destroy
```

### Azure
```bash
cd azure
terraform destroy
```

### GCP
```bash
cd gcp
terraform destroy
```

---

## Support

For issues related to:
- **Qualys Sensor**: Contact Qualys Support
- **Deployment Templates**: Open an issue in this repository
- **Cloud Providers**: Consult respective cloud provider documentation
