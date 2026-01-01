# Qualys Container Security Registry Sensor - Multi-Cloud Architecture

## Overview

This document describes the architecture for deploying Qualys Container Security Registry Sensor across AWS, Azure, and GCP.

## Architecture Comparison

### AWS ECS

**Deployment Model**: ECS with EC2 instances using DAEMON scheduling strategy

**Components**:
- ECS Cluster with EC2 instances
- Auto Scaling Group (1-10 instances)
- VPC with public/private subnets and NAT gateways
- IAM roles for ECR access and task execution
- CloudWatch Logs for monitoring

**Network Architecture**:
```
VPC (172.20.250.0/24)
├── Public Subnets (2x /26)
│   ├── NAT Gateway 1
│   └── NAT Gateway 2
└── Private Subnets (2x /26)
    ├── ECS Instance 1 -> Qualys Task
    └── ECS Instance 2 -> Qualys Task
```

**Scaling**: One Qualys task per EC2 instance (DAEMON strategy)

**Container Runtime**: Docker (Amazon Linux 2 ECS-optimized AMI)

### AWS EKS

**Deployment Model**: Kubernetes DaemonSet on EKS

**Components**:
- EKS Cluster with managed node groups
- VPC with public/private subnets and NAT gateways
- IAM roles for node groups and OIDC provider
- KMS encryption for cluster secrets
- CloudWatch Logs for monitoring

**Network Architecture**:
```
VPC (172.20.0.0/16)
├── Public Subnets (2x /24)
│   ├── NAT Gateway 1
│   └── NAT Gateway 2
└── Private Subnets (2x /24)
    ├── Node 1 -> Qualys Pod (DaemonSet)
    └── Node 2 -> Qualys Pod (DaemonSet)
```

**Scaling**: One Qualys pod per node (DaemonSet)

**Container Runtime**: containerd (EKS managed nodes)

### Azure AKS

**Deployment Model**: Kubernetes DaemonSet on AKS

**Components**:
- AKS Cluster with managed node pools
- Virtual Network with dedicated subnet
- Azure Container Registry for images
- Log Analytics Workspace for monitoring
- Managed Identity for authentication

**Network Architecture**:
```
VNet (10.1.0.0/16)
└── AKS Subnet (10.1.0.0/20)
    ├── Pod Network (10.1.64.0/18)
    └── Service Network (10.2.0.0/16)

Node Pool (Auto-scaling: 1-10 nodes)
├── Node 1 -> Qualys Pod (DaemonSet)
├── Node 2 -> Qualys Pod (DaemonSet)
└── Node N -> Qualys Pod (DaemonSet)
```

**Scaling**: One Qualys pod per node (DaemonSet)

**Container Runtime**: containerd (default on AKS)

### GCP GKE

**Deployment Model**: Kubernetes DaemonSet on GKE

**Components**:
- Regional GKE Cluster (multi-zone)
- VPC with custom subnet ranges
- Google Container Registry for images
- Cloud Monitoring and Logging
- Workload Identity for authentication

**Network Architecture**:
```
VPC Network (10.0.0.0/20)
├── Primary Subnet (10.0.0.0/20)
├── Pods Secondary Range (10.1.0.0/16)
└── Services Secondary Range (10.2.0.0/16)

Regional Cluster (us-central1)
├── Zone A -> Node Pool (1-10 nodes)
├── Zone B -> Node Pool (1-10 nodes)
└── Each Node -> Qualys Pod (DaemonSet)
```

**Scaling**: One Qualys pod per node (DaemonSet)

**Container Runtime**: containerd (default on GKE)

## Common Configuration

### Sensor Configuration

```yaml
Args:
  - --registry-sensor
  - --storage-driver-type overlay2
  - --perform-sca-scan
  - --optimize-image-scans
  - --sensor-without-persistent-storage
  - --enable-console-logs
```

### Environment Variables

```yaml
ACTIVATIONID: <from-secret>
CUSTOMERID: <from-secret>
POD_URL: <qualys-platform-url>
```

### Volume Mounts

| Volume | Mount Path | Purpose |
|--------|-----------|---------|
| Docker Socket | /var/run/docker.sock | Access Docker daemon |
| Containerd Socket | /run/containerd/containerd.sock | Access containerd |
| Docker Root | /var/lib/docker | Scan Docker images |
| Containerd Root | /var/lib/containerd | Scan containerd images |

### Resource Allocation

```yaml
Requests:
  CPU: 250m
  Memory: 512Mi
Limits:
  CPU: 500m
  Memory: 1Gi
```

## Security Architecture

### Credential Management

| Cloud | Method |
|-------|--------|
| AWS ECS | Secrets Manager with KMS encryption |
| AWS EKS | Kubernetes Secrets (OIDC for IAM integration) |
| Azure | Terraform Variables (sensitive) to Kubernetes Secret |
| GCP | Terraform Variables (sensitive) to Kubernetes Secret |

### Network Security

All deployments use private networks:

1. **Compute instances in private subnets**
   - No direct internet access
   - Outbound only through NAT

2. **NAT Gateway**
   - Required for Qualys platform communication
   - Required for container registry access

3. **Security Groups/Firewall Rules**
   - Minimal inbound rules
   - Outbound HTTPS to Qualys platform
   - Outbound access to container registries

### Container Permissions

The sensor requires elevated capabilities:

```yaml
Capabilities:
  - SYS_ADMIN
  - DAC_OVERRIDE
  - SETUID
  - SETGID
```

## Monitoring and Logging

| Cloud | Service | Log Location |
|-------|---------|--------------|
| AWS ECS | CloudWatch Logs | /ecs/{cluster}/qualys-container-sensor |
| AWS EKS | CloudWatch Logs | /aws/eks/{cluster}/cluster |
| Azure | Log Analytics | AKS cluster workspace |
| GCP | Cloud Logging | GKE cluster logs |

## Scaling Behavior

### AWS ECS
- Auto Scaling Group adjusts EC2 instance count
- ECS DAEMON strategy ensures one task per instance

### AWS EKS
- Managed node group auto-scales based on demand
- DaemonSet automatically schedules pod on new nodes

### Azure AKS
- Node pool auto-scales based on demand
- DaemonSet automatically schedules pod on new nodes

### GCP GKE
- Node pool auto-scales in each zone
- DaemonSet automatically schedules pod on new nodes
- Multi-zone deployment provides HA

## High Availability

### AWS ECS
- Multi-AZ deployment (2 AZs)
- Auto Scaling Group maintains desired capacity
- ECS service automatically replaces failed tasks

### AWS EKS
- Multi-AZ deployment (2 AZs)
- Managed node groups handle node replacement
- Pod automatically rescheduled on node failure

### Azure AKS
- Multi-zone node pool (availability zones)
- Node auto-repair enabled
- Pod automatically rescheduled on node failure

### GCP GKE
- Regional cluster (multi-zone by default)
- Node auto-repair enabled
- Pod automatically rescheduled on node failure
- Control plane is highly available across zones
