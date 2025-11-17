# Qualys Registry Sensor - Multi-Cloud Architecture

## Overview

This document describes the architecture and design decisions for deploying Qualys Container Registry Sensor across AWS, Azure, and GCP.

## Design Principles

1. **Consistency**: Maintain similar deployment patterns across all cloud providers
2. **Scalability**: Auto-scaling capabilities on all platforms
3. **Security**: Private networks, minimal permissions, secure credential management
4. **Observability**: Integrated logging and monitoring on each platform
5. **Automation**: Infrastructure-as-Code for reproducible deployments

## Architecture Comparison

### AWS ECS

**Deployment Model**: ECS with EC2 instances using DAEMON scheduling strategy

**Key Components**:
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
    ├── ECS Instance 1 → Qualys Task
    └── ECS Instance 2 → Qualys Task
```

**Scaling**: One Qualys task per EC2 instance (DAEMON strategy)

**Container Runtime**: Docker (Amazon Linux 2 ECS-optimized AMI)

### Azure AKS

**Deployment Model**: Kubernetes DaemonSet on AKS

**Key Components**:
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
├── Node 1 → Qualys Pod (DaemonSet)
├── Node 2 → Qualys Pod (DaemonSet)
└── Node N → Qualys Pod (DaemonSet)
```

**Scaling**: One Qualys pod per node (DaemonSet)

**Container Runtime**: containerd (default on AKS)

### GCP GKE

**Deployment Model**: Kubernetes DaemonSet on GKE

**Key Components**:
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
├── Zone A → Node Pool (1-10 nodes)
├── Zone B → Node Pool (1-10 nodes)
└── Each Node → Qualys Pod (DaemonSet)
```

**Scaling**: One Qualys pod per node (DaemonSet)

**Container Runtime**: containerd (default on GKE)

## Technology Choices

### Why Kubernetes for Azure and GCP?

The Qualys Container Sensor requires:
- Access to container runtime socket (Docker or containerd)
- Access to container storage directories
- One sensor per compute instance (daemon pattern)

**Considered Alternatives**:

1. **Azure Container Instances (ACI)**
   - ❌ No Docker/containerd socket access
   - ❌ No host path mounting
   - ❌ Not suitable for registry scanning

2. **GCP Cloud Run**
   - ❌ Serverless, no socket access
   - ❌ Requires HTTP endpoint
   - ❌ Not suitable for registry scanning

3. **Kubernetes (AKS/GKE)** ✅
   - ✅ Full control over pod scheduling
   - ✅ DaemonSet pattern matches ECS DAEMON
   - ✅ Socket and volume mounting supported
   - ✅ Multi-runtime support (Docker/containerd)
   - ✅ Native auto-scaling

### Infrastructure-as-Code Tools

| Cloud | Tool | Rationale |
|-------|------|-----------|
| AWS | CloudFormation | Native AWS service, JSON format matches existing template |
| Azure | Terraform | De facto standard for Azure, HCL is clear and maintainable |
| GCP | Terraform | Official Google recommendation, excellent GCP provider |

## Common Configuration

All deployments share these characteristics:

### Qualys Sensor Configuration

```yaml
Command/Args:
  - --registry-sensor            # Registry scanning mode
  - --storage-driver-type overlay2
  - --perform-sca-scan          # Software Composition Analysis
  - --optimize-image-scans      # Performance optimization
  - --sensor-without-persistent-storage
  - --enable-console-logs       # Logging to stdout/stderr
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
| Docker Socket | `/var/run/docker.sock` | Access Docker daemon |
| Containerd Socket | `/run/containerd/containerd.sock` | Access containerd |
| Docker Root | `/var/lib/docker` | Scan Docker images |
| Containerd Root | `/var/lib/containerd` | Scan containerd images |

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
| AWS | CloudFormation Parameters (NoEcho) → Environment Variables |
| Azure | Terraform Variables (sensitive) → Kubernetes Secret |
| GCP | Terraform Variables (sensitive) → Kubernetes Secret |

**Best Practices**:
- Use external secret managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)
- Never commit credentials to version control
- Rotate credentials regularly

### Network Security

All deployments use **private networks** with the following pattern:

1. **Compute instances in private subnets**
   - No direct internet access
   - Outbound only through NAT

2. **NAT Gateway/Internet Gateway**
   - Required for Qualys platform communication
   - Required for container registry access

3. **Security Groups/Firewall Rules**
   - Minimal inbound rules
   - Outbound HTTPS to Qualys platform
   - Outbound access to container registries

### Container Permissions

The Qualys sensor requires elevated capabilities:

```yaml
Capabilities:
  - SYS_ADMIN      # For mount operations
  - DAC_OVERRIDE   # Bypass file permission checks
  - SETUID         # Set user ID
  - SETGID         # Set group ID
```

**Note**: While these are privileged capabilities, they are necessary for:
- Accessing container filesystems
- Reading image layers
- Scanning container contents

## Monitoring and Logging

| Cloud | Service | Log Location |
|-------|---------|--------------|
| AWS | CloudWatch Logs | `/ecs/{cluster}/qualys-container-sensor` |
| Azure | Log Analytics | AKS cluster workspace |
| GCP | Cloud Logging | GKE cluster logs |

**Common Log Queries**:

```bash
# View sensor startup
kubectl logs -n qualys-sensor -l app=qualys-container-sensor --tail=50

# View sensor errors
kubectl logs -n qualys-sensor -l app=qualys-container-sensor | grep ERROR

# View scanning activity
kubectl logs -n qualys-sensor -l app=qualys-container-sensor | grep scan
```

## Scaling Behavior

### AWS ECS
- Auto Scaling Group adjusts EC2 instance count
- ECS DAEMON strategy ensures one task per instance
- Scaling time: 2-3 minutes (EC2 launch time)

### Azure AKS
- Node pool auto-scales based on demand
- DaemonSet automatically schedules pod on new nodes
- Scaling time: 1-2 minutes (VM allocation)

### GCP GKE
- Node pool auto-scales in each zone
- DaemonSet automatically schedules pod on new nodes
- Scaling time: 1-2 minutes (VM allocation)
- Multi-zone deployment provides HA

## Cost Considerations

### AWS ECS
- EC2 instances (c5.large): ~$62/month per instance
- NAT Gateway: ~$32/month per gateway
- Data transfer: Variable
- **Estimated monthly cost (2 instances)**: ~$160-200

### Azure AKS
- AKS cluster: Free (control plane)
- VM instances (Standard_D2s_v3): ~$70/month per node
- NAT Gateway: ~$33/month
- Log Analytics: ~$2.30/GB
- **Estimated monthly cost (2 nodes)**: ~$175-225

### GCP GKE
- GKE cluster: $73/month (control plane)
- VM instances (e2-standard-2): ~$49/month per node per zone
- NAT Gateway: ~$32/month
- Network egress: Variable
- **Estimated monthly cost (2 nodes, 2 zones)**: ~$200-250

**Cost Optimization Tips**:
1. Use auto-scaling to scale down during off-peak hours
2. Use spot/preemptible instances for non-production
3. Monitor and optimize network egress costs
4. Use appropriate instance/VM sizes for workload

## High Availability

### AWS ECS
- Multi-AZ deployment (2 AZs)
- Auto Scaling Group maintains desired capacity
- ECS service automatically replaces failed tasks

### Azure AKS
- Multi-zone node pool (availability zones)
- Node auto-repair enabled
- Pod automatically rescheduled on node failure

### GCP GKE
- Regional cluster (multi-zone by default)
- Node auto-repair enabled
- Pod automatically rescheduled on node failure
- Control plane is highly available across zones

## Disaster Recovery

### Backup Strategy
1. **Infrastructure**: All IaC templates in version control
2. **Configuration**: Terraform state stored remotely
3. **Credentials**: External secret managers

### Recovery Steps
1. Deploy infrastructure from IaC templates
2. Apply Kubernetes manifests
3. Restore credentials from secret manager
4. Verify sensor connectivity to Qualys platform

**Recovery Time Objective (RTO)**: 15-30 minutes
**Recovery Point Objective (RPO)**: N/A (stateless sensors)

## Migration Path

To migrate between clouds:

1. **Deploy target cloud infrastructure**
2. **Push Qualys image to target registry**
3. **Deploy sensors on new platform**
4. **Validate scanning is working**
5. **Decommission old platform**

**Note**: Sensors are stateless - no data migration required

## Future Enhancements

Potential improvements:
1. Helm charts for Kubernetes deployments
2. GitOps integration (ArgoCD/Flux)
3. Multi-cluster deployments
4. Advanced monitoring dashboards
5. Cost optimization automation
6. Integration with cloud-native secret managers
7. Support for ARM-based instances
8. Kustomize overlays for environment-specific configs

## References

- [Qualys Container Security Documentation](https://www.qualys.com/docs/qualys-container-security.pdf)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Azure AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)
- [GCP GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
