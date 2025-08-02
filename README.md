# Qualys Container Sensor ECS Deployment

CloudFormation template to deploy Qualys Container Sensor on ECS with EC2 instances and optional VPC creation.

## Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `QualysImage` | Private ECR image URI | `123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest` |
| `QualysActivationId` | Qualys activation ID (NoEcho) | `YOUR_ACTIVATION_ID` |
| `QualysCustomerId` | Qualys customer ID (NoEcho) | `YOUR_CUSTOMER_ID` |
| `QualysPodUrl` | Qualys Container Security Server URL | `QUALYS_POD_URL` |

## Optional Parameters

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

## Deployment Methods

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
  --capabilities CAPABILITY_IAM
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

## Architecture

### With CreateVpc=true
- **VPC**: 172.20.250.0/24
- **Public Subnets**: 2x /26 with NAT gateways  
- **Private Subnets**: 2x /26 for ECS instances
- **ECS Cluster**: c5.large instances across 2 AZs
- **Tasks**: 1 Qualys sensor per instance (2 total)

### With CreateVpc=false
- Uses existing VPC and subnets
- Requires proper NAT gateway/internet access for ECR

## IAM Roles Created

| Role | Purpose |
|------|---------|
| `QualysECRRepositoryforEC2` | EC2 instance ECR access |
| `QualysContainerSensorTaskRole` | Task runtime (minimal permissions) |
| `QualysECRExecutionRole` | Image pulling and logging |

## Outputs

| Output | Description |
|--------|-------------|
| `ClusterName` | ECS cluster name |
| `ClusterArn` | ECS cluster ARN |
| `VpcId` | VPC ID used |
| `PrivateSubnetIds` | Private subnet IDs |
| `TaskDefinitionArn` | Qualys task definition ARN |
| `ServiceName` | ECS service name |

## Requirements

- Private ECR repository with Qualys container image
- Valid Qualys activation ID and customer ID
- AWS CLI configured with appropriate permissions
- IAM permissions to create roles, EC2 instances, VPC resources

## Notes

- Each EC2 instance runs one Qualys sensor task
- Tasks automatically distribute across instances and AZs
- Container requires Docker socket and specific volume mounts
- NAT gateway required for ECR access from private subnets
