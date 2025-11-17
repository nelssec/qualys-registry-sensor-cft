# Qualys Registry Sensor - Multi-Cloud Deployment

Deploy Qualys Container Registry Sensor across AWS, Azure, and GCP with infrastructure-as-code templates.

## Overview

This repository provides deployment templates for Qualys Container Registry Sensor on:
- **AWS**: ECS with EC2 instances (CloudFormation)
- **Azure**: AKS (Azure Kubernetes Service) with Terraform
- **GCP**: GKE (Google Kubernetes Engine) with Terraform

---

## Quick Start

Choose your cloud provider:
- [AWS ECS Deployment](#aws-ecs-deployment)
- [Azure AKS Deployment](#azure-aks-deployment)
- [GCP GKE Deployment](#gcp-gke-deployment)

---

## AWS ECS Deployment

CloudFormation template to deploy Qualys Container Sensor on ECS with EC2 instances and optional VPC creation.

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `QualysImage` | Private ECR image URI | `123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest` |
| `QualysActivationId` | Qualys activation ID (NoEcho) | `YOUR_ACTIVATION_ID` |
| `QualysCustomerId` | Qualys customer ID (NoEcho) | `YOUR_CUSTOMER_ID` |
| `QualysPodUrl` | Qualys Container Security Server URL | `QUALYS_POD_URL` |

### Optional Parameters

| Parameter | Default | Options | Description |
|-----------|---------|---------|-------------|
| `CreateVpc` | `false` | `true`, `false` | Create new VPC with private subnets and NAT gateways |
| `ClusterName` | `qualys-registry-cluster` | String | ECS cluster name |
| `InstanceType` | `c5.large` | `c5.large`, `c5.xlarge`, etc. | EC2 instance type |
| `DesiredCapacity` | `2` | 1-10 | Number of EC2 instances and Qualys tasks |
| `MinSize` | `1` | 1-10 | ASG minimum size |
| `MaxSize` | `3` | 1-20 | ASG maximum size |
| `KeyName` | Empty | String | EC2 Key Pair for SSH access |
| `VpcId` | Empty | `vpc-xxxxx` | Existing VPC ID (required if CreateVpc=false) |
| `SubnetIds` | Empty | `subnet-xxx,subnet-yyy` | Existing subnet IDs (required if CreateVpc=false) |

### Deployment Methods

### CLI Deployment (Recommended)
```bash
aws cloudformation create-stack \
  --stack-name qualys-ecs-cluster \
  --template-body file://cssensor-aws-ecs.json \
  --parameters \
    ParameterKey=QualysImage,ParameterValue=123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest \
    ParameterKey=CreateVpc,ParameterValue=true \
    ParameterKey=QualysPodUrl,ParameterValue=QUALYS_POD_URL \
    ParameterKey=QualysActivationId,ParameterValue=YOUR_ACTIVATION_ID \
    ParameterKey=QualysCustomerId,ParameterValue=YOUR_CUSTOMER_ID \
  --capabilities CAPABILITY_NAMED_IAM
```

### Console Deployment
1. Upload `cssensor-aws-ecs.json` to CloudFormation console
2. Enter required parameters in the Parameters section
3. Check "I acknowledge that AWS CloudFormation might create IAM resources"
4. Create stack

### Parameter File Deployment
Create `parameters.json`:
```json
[
  {"ParameterKey": "QualysImage", "ParameterValue": "123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest"},
  {"ParameterKey": "CreateVpc", "ParameterValue": "true"},
  {"ParameterKey": "QualysPodUrl", "ParameterValue": "QUALYS_POD_URL"},
  {"ParameterKey": "QualysActivationId", "ParameterValue": "YOUR_ACTIVATION_ID"},
  {"ParameterKey": "QualysCustomerId", "ParameterValue": "YOUR_CUSTOMER_ID"}
]
```

Deploy:
```bash
aws cloudformation create-stack \
  --stack-name qualys-ecs-cluster \
  --template-body file://cssensor-aws-ecs.json \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM
```

### Architecture

### With CreateVpc=true
- **VPC**: 172.20.250.0/24
- **Public Subnets**: 2x /26 with NAT gateways  
- **Private Subnets**: 2x /26 for ECS instances
- **ECS Cluster**: c5.large instances across 2 AZs
- **Tasks**: 1 Qualys sensor per instance (2 total)

### With CreateVpc=false
- Uses existing VPC and subnets
- Requires proper NAT gateway/internet access for ECR

### IAM Roles Created

| Role | Purpose |
|------|---------|
| `QualysECRRepositoryforEC2` | EC2 instance ECR access |
| `QualysContainerSensorTaskRole` | Task runtime (minimal permissions) |
| `QualysECRExecutionRole` | Image pulling and logging |

### Outputs

| Output | Description |
|--------|-------------|
| `ClusterName` | ECS cluster name |
| `ClusterArn` | ECS cluster ARN |
| `VpcId` | VPC ID used |
| `PrivateSubnetIds` | Private subnet IDs |
| `TaskDefinitionArn` | Qualys task definition ARN |
| `ServiceName` | ECS service name |

### Requirements

- Private ECR repository with Qualys container image
- Valid Qualys activation ID and customer ID
- AWS CLI configured with appropriate permissions
- IAM permissions to create roles, EC2 instances, VPC resources

### Notes

- Each EC2 instance runs one Qualys sensor task
- Tasks automatically distribute across instances and AZs
- Container requires Docker socket and specific volume mounts
- NAT gateway required for ECR access from private subnets

---

## Azure AKS Deployment

Terraform template to deploy Qualys Container Sensor on Azure Kubernetes Service (AKS) with managed node pools.

### Prerequisites

- Azure CLI (`az`) installed and configured
- Terraform >= 1.0
- kubectl installed
- Valid Azure subscription

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `qualys_activation_id` | Qualys activation ID (sensitive) | `YOUR_ACTIVATION_ID` |
| `qualys_customer_id` | Qualys customer ID (sensitive) | `YOUR_CUSTOMER_ID` |
| `qualys_pod_url` | Qualys Container Security Server URL | `https://qualysapi.qualys.com` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `resource_group_name` | `qualys-registry-sensor-rg` | Name of the resource group |
| `location` | `eastus` | Azure region |
| `cluster_name` | `qualys-registry-cluster` | Name of the AKS cluster |
| `node_count` | `2` | Number of nodes in the default pool |
| `node_vm_size` | `Standard_D2s_v3` | VM size for nodes |
| `kubernetes_version` | `1.28` | Kubernetes version |
| `create_acr` | `true` | Create Azure Container Registry |

### Deployment Steps

#### 1. Prepare Configuration

```bash
cd azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

#### 2. Deploy Infrastructure

```bash
# Option A: Use the automated deployment script
chmod +x deploy.sh
./deploy.sh

# Option B: Manual deployment
terraform init
terraform plan
terraform apply
```

#### 3. Configure kubectl

```bash
az aks get-credentials \
  --resource-group qualys-registry-sensor-rg \
  --name qualys-registry-cluster
```

#### 4. Deploy Qualys Sensor

```bash
# Update the image in kubernetes/qualys-daemonset.yaml with your ACR location
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
```

#### 5. Verify Deployment

```bash
kubectl get pods -n qualys-sensor
kubectl logs -n qualys-sensor -l app=qualys-container-sensor
```

### Architecture

- **AKS Cluster**: Managed Kubernetes with auto-scaling node pools
- **Virtual Network**: 10.1.0.0/16 with dedicated subnet for AKS
- **Container Registry**: Azure Container Registry for Qualys images
- **Monitoring**: Azure Monitor and Log Analytics integration
- **DaemonSet**: One Qualys sensor pod per node

### Outputs

| Output | Description |
|--------|-------------|
| `aks_cluster_name` | Name of the AKS cluster |
| `aks_cluster_id` | ID of the AKS cluster |
| `acr_login_server` | ACR login server URL |
| `get_credentials_command` | Command to configure kubectl |

### Notes

- Sensors run as a Kubernetes DaemonSet (one pod per node)
- Supports both Docker and containerd runtimes
- Auto-scales with the node pool
- Requires system-level capabilities for container scanning

---

## GCP GKE Deployment

Terraform template to deploy Qualys Container Sensor on Google Kubernetes Engine (GKE) with managed node pools.

### Prerequisites

- Google Cloud SDK (`gcloud`) installed and configured
- Terraform >= 1.0
- kubectl installed
- Valid GCP project with billing enabled

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP Project ID | `my-project-123456` |
| `qualys_activation_id` | Qualys activation ID (sensitive) | `YOUR_ACTIVATION_ID` |
| `qualys_customer_id` | Qualys customer ID (sensitive) | `YOUR_CUSTOMER_ID` |
| `qualys_pod_url` | Qualys Container Security Server URL | `https://qualysapi.qualys.com` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-central1` | GCP region |
| `cluster_name` | `qualys-registry-cluster` | Name of the GKE cluster |
| `node_count` | `1` | Number of nodes per zone |
| `machine_type` | `e2-standard-2` | Machine type for nodes |
| `kubernetes_version` | `1.28` | Kubernetes version |
| `network_name` | `qualys-registry-network` | VPC network name |

### Deployment Steps

#### 1. Prepare Configuration

```bash
cd gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

#### 2. Authenticate with GCP

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

#### 3. Deploy Infrastructure

```bash
# Option A: Use the automated deployment script
chmod +x deploy.sh
./deploy.sh

# Option B: Manual deployment
terraform init
terraform plan
terraform apply
```

#### 4. Configure kubectl

```bash
gcloud container clusters get-credentials qualys-registry-cluster \
  --region us-central1 \
  --project YOUR_PROJECT_ID
```

#### 5. Deploy Qualys Sensor

```bash
# Update the image in kubernetes/qualys-daemonset.yaml with your GCR location
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
```

#### 6. Verify Deployment

```bash
kubectl get pods -n qualys-sensor
kubectl logs -n qualys-sensor -l app=qualys-container-sensor
```

### Architecture

- **GKE Cluster**: Regional cluster with multi-zone node pools
- **VPC Network**: Custom VPC with dedicated subnet ranges
- **Container Registry**: Google Container Registry for Qualys images
- **Monitoring**: Google Cloud Monitoring and Logging integration
- **Workload Identity**: Enabled for secure pod authentication
- **DaemonSet**: One Qualys sensor pod per node

### Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `cluster_endpoint` | GKE cluster endpoint |
| `get_credentials_command` | Command to configure kubectl |
| `qualys_image_location` | Expected GCR image location |

### Notes

- Sensors run as a Kubernetes DaemonSet (one pod per node)
- Supports both Docker and containerd runtimes
- Regional cluster provides high availability
- Auto-scaling enabled (1-10 nodes per zone)
- Network policy enabled for enhanced security

---

## Common Operations

### Viewing Sensor Logs

```bash
# List all sensor pods
kubectl get pods -n qualys-sensor

# View logs from all sensor pods
kubectl logs -n qualys-sensor -l app=qualys-container-sensor --tail=100

# View logs from a specific pod
kubectl logs -n qualys-sensor <pod-name>

# Follow logs in real-time
kubectl logs -n qualys-sensor -l app=qualys-container-sensor -f
```

### Updating Sensor Image

```bash
# Update the image in the DaemonSet
kubectl set image daemonset/qualys-container-sensor \
  qualys-container-sensor=<new-image> \
  -n qualys-sensor

# Or edit the DaemonSet directly
kubectl edit daemonset qualys-container-sensor -n qualys-sensor
```

### Troubleshooting

```bash
# Check DaemonSet status
kubectl describe daemonset qualys-container-sensor -n qualys-sensor

# Check pod status and events
kubectl describe pod -n qualys-sensor <pod-name>

# Check if secrets are properly configured
kubectl get secret qualys-credentials -n qualys-sensor -o yaml
```

### Cleanup

#### AWS
```bash
aws cloudformation delete-stack --stack-name qualys-ecs-cluster
```

#### Azure
```bash
cd azure
terraform destroy
```

#### GCP
```bash
cd gcp
terraform destroy
```

---

## Security Considerations

1. **Credentials Management**
   - Use secure methods to store Qualys credentials (e.g., AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)
   - Never commit credentials to version control
   - Rotate credentials regularly

2. **Network Security**
   - Sensors require outbound internet access to Qualys platform
   - Use private subnets with NAT gateway/proxy
   - Configure appropriate security groups/firewall rules

3. **Container Permissions**
   - Sensors require elevated capabilities to scan containers
   - Review and understand the required permissions before deployment
   - Follow principle of least privilege

4. **Image Security**
   - Store Qualys sensor images in private registries
   - Scan sensor images for vulnerabilities
   - Keep sensor images up to date

---

## Support

For issues related to:
- **Qualys Sensor**: Contact Qualys Support
- **Deployment Templates**: Open an issue in this repository
- **Cloud Provider Issues**: Consult respective cloud provider documentation

## License

This project is licensed under the MIT License - see the LICENSE file for details.
