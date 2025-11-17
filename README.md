# Qualys Registry Sensor - Multi-Cloud Deployment

Deploy Qualys Container Registry Sensor across AWS, Azure, and GCP with Terraform.

## Overview

Terraform configurations for deploying Qualys Container Registry Sensor on:
- **AWS ECS**: EC2-based ECS cluster with optional VPC creation
- **Azure**: VM Scale Sets with Docker
- **GCP**: Managed Instance Groups with Container-Optimized OS

All deployments use simple VM-based infrastructure running Docker containers. No Kubernetes complexity.

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

create_vpc = true

qualys_image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest"
qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"
```

To use an existing VPC instead, set `create_vpc = false` and provide `vpc_id` and `subnet_ids`.

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

## Azure VM Scale Sets Deployment

Terraform configuration for VM Scale Sets running Docker containers.

### Prerequisites

- Azure CLI configured with valid subscription
- Terraform >= 1.0
- Qualys container image in ACR or external registry

### Configuration

Edit `azure/terraform.tfvars`:

```hcl
resource_group_name = "qualys-registry-sensor-rg"
location            = "eastus"
cluster_name        = "qualys-registry-cluster"
instance_count      = 2
vm_size             = "Standard_D2s_v3"

create_acr = true

qualys_image         = "qualysregistryclusteracr.azurecr.io/qualys/qcs-sensor:latest"
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

### Architecture

- VM Scale Sets with Ubuntu 22.04 and Docker
- VNet: 10.1.0.0/16 with dedicated subnet
- NAT Gateway for secure outbound access
- Network Security Group (HTTPS + DNS only)
- Azure Container Registry for Qualys images
- Managed identity for ACR pull access
- Sensor runs as privileged Docker container on each VM

### Outputs

```bash
terraform output vmss_name
terraform output acr_login_server
terraform output qualys_image_location
```

---

## GCP Managed Instance Groups Deployment

Terraform configuration for Managed Instance Groups using Container-Optimized OS.

### Prerequisites

- Google Cloud SDK configured with valid project
- Terraform >= 1.0
- Qualys container image in GCR or Artifact Registry

### Configuration

Edit `gcp/terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

cluster_name   = "qualys-registry-cluster"
instance_count = 2
machine_type   = "e2-standard-2"

qualys_image         = "gcr.io/your-gcp-project-id/qualys/qcs-sensor:latest"
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

### Architecture

- Managed Instance Groups with Container-Optimized OS
- Container declaration in instance template metadata
- Custom VPC with dedicated subnet
- Cloud NAT for secure outbound access
- Firewall rules (HTTPS + DNS egress only)
- Service account with minimal permissions
- Auto-healing for instance health
- One Qualys sensor container per VM

### Outputs

```bash
terraform output mig_name
terraform output network_name
terraform output qualys_image_location
```

---

## Common Operations

### View Logs

**AWS**:
```bash
aws logs tail /ecs/qualys-registry-cluster/qualys-sensor --follow
```

**Azure**:
```bash
az vmss list-instances --resource-group qualys-registry-sensor-rg --name qualys-registry-cluster-vmss
```

**GCP**:
```bash
gcloud compute instances list --filter="name~'qualys-registry-cluster'"
gcloud compute ssh qualys-registry-cluster-instance-XXXX --command="docker logs qualys-container-sensor"
```

### Update Sensor Image

After pushing new image to registry:

**AWS**:
```bash
aws ecs update-service --cluster qualys-registry-cluster --service qualys-registry-cluster-qualys-sensor --force-new-deployment
```

**Azure**:
```bash
az vmss update-instances --resource-group qualys-registry-sensor-rg --name qualys-registry-cluster-vmss --instance-ids '*'
```

**GCP**:
```bash
gcloud compute instance-groups managed rolling-action replace qualys-registry-cluster-mig --zone us-central1-a
```

---

## Security Considerations

**Credentials**:
- Store Qualys credentials securely (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)
- Never commit credentials to version control
- Rotate credentials regularly
- Credentials passed as environment variables to containers

**Network**:
- Sensors require outbound internet access to Qualys platform
- All deployments use private subnets/networks with NAT gateway
- Security groups/firewall rules allow only HTTPS (443) and DNS (53) egress
- No inbound access required

**Permissions**:
- AWS: Minimal ECS task execution permissions
- Azure: AcrPull role for container registry access only
- GCP: Minimal scopes (storage read-only, logging, monitoring)
- All IAM roles/identities follow least privilege principle

**Container Security**:
- Sensors run in privileged mode (required for Docker socket access)
- Access to host Docker socket for container scanning
- Isolated per VM - one sensor per instance

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
