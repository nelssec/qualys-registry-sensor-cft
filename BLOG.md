# Deploying Qualys Container Security Registry Sensor Across Multi-Cloud Environments

This guide provides a comprehensive overview of deploying the Qualys Container Security Registry Sensor across AWS (ECS and EKS), Azure AKS, and GCP GKE with enterprise-grade security controls aligned with CIS Benchmarks.

## Architecture Overview

```mermaid
flowchart TB
    subgraph "Qualys Platform"
        QP[Qualys Cloud Platform]
    end

    subgraph "AWS ECS"
        subgraph "VPC - 172.20.250.0/24"
            subgraph "Private Subnets ECS"
                ECS[ECS Cluster]
                EC2[EC2 Instances]
                SENSOR1[Qualys Container Security Registry Sensor]
            end
            subgraph "Public Subnets ECS"
                NAT1[NAT Gateway]
            end
        end
        SM[Secrets Manager]
        CW[CloudWatch Logs]
        KMS[KMS Keys]
    end

    subgraph "AWS EKS"
        subgraph "VPC - 172.20.0.0/16"
            subgraph "Private Subnets EKS"
                EKS[EKS Cluster]
                NODES[Node Groups]
                SENSOR1B[Qualys Registry Sensor DaemonSet]
            end
            subgraph "Public Subnets EKS"
                NAT1B[NAT Gateway]
            end
        end
        OIDC[OIDC Provider]
        CW2[CloudWatch Logs]
        KMS2[KMS Keys]
    end

    subgraph "Azure"
        subgraph "VNet - 10.1.0.0/16"
            subgraph "AKS Subnet"
                AKS[AKS Cluster]
                NODES1[Node Pool]
                SENSOR2[Qualys Registry Sensor DaemonSet]
            end
        end
        NAT2[NAT Gateway]
        KV[Key Vault]
        LA[Log Analytics]
        DEF[Defender for Containers]
    end

    subgraph "GCP"
        subgraph "VPC - 10.0.0.0/20"
            subgraph "GKE Subnet"
                GKE[GKE Cluster]
                NODES2[Node Pool]
                SENSOR3[Qualys Registry Sensor DaemonSet]
            end
        end
        NAT3[Cloud NAT]
        GSM[Secret Manager]
        CL[Cloud Logging]
        BIN[Binary Authorization]
    end

    SENSOR1 -->|HTTPS 443| NAT1 -->|Scan Results| QP
    SENSOR1B -->|HTTPS 443| NAT1B -->|Scan Results| QP
    SENSOR2 -->|HTTPS 443| NAT2 -->|Scan Results| QP
    SENSOR3 -->|HTTPS 443| NAT3 -->|Scan Results| QP

    EC2 --> SM
    EKS --> OIDC
    AKS --> KV
    GKE --> GSM
```

## Deployment Workflow

```mermaid
sequenceDiagram
    participant User
    participant Terraform
    participant Cloud as Cloud Provider
    participant K8s as Kubernetes
    participant Qualys as Qualys Platform

    User->>Terraform: terraform init
    Terraform->>Cloud: Initialize backend

    User->>Terraform: terraform plan
    Terraform->>Cloud: Validate resources
    Terraform-->>User: Show execution plan

    User->>Terraform: terraform apply

    rect rgb(200, 220, 240)
        Note over Terraform,Cloud: Infrastructure Provisioning
        Terraform->>Cloud: Create VPC/VNet
        Terraform->>Cloud: Create NAT Gateway
        Terraform->>Cloud: Create Security Groups
        Terraform->>Cloud: Create KMS Keys
        Terraform->>Cloud: Store Secrets
        Terraform->>Cloud: Create Cluster (ECS/AKS/GKE)
    end

    rect rgb(220, 240, 200)
        Note over K8s,Qualys: Registry Sensor Deployment
        Terraform->>K8s: Deploy DaemonSet
        K8s->>K8s: Schedule pods on all nodes
        K8s->>Qualys: Registry Sensor registration
        Qualys-->>K8s: Activation confirmed
    end

    rect rgb(240, 220, 200)
        Note over K8s,Qualys: Continuous Scanning
        loop Every scan interval
            K8s->>K8s: Scan container images
            K8s->>Qualys: Send vulnerability data
            Qualys-->>User: Dashboard updates
        end
    end
```

## Security Architecture

```mermaid
flowchart LR
    subgraph "Defense in Depth"
        subgraph "Layer 1: Network"
            FW[Firewall Rules]
            NSG[Network Security Groups]
            NP[Network Policies]
        end

        subgraph "Layer 2: Identity"
            IAM[IAM Roles]
            WI[Workload Identity]
            SA[Service Accounts]
        end

        subgraph "Layer 3: Secrets"
            SM[Secrets Manager]
            KV[Key Vault]
            GSM[GCP Secret Manager]
        end

        subgraph "Layer 4: Encryption"
            KMS[KMS Encryption]
            TLS[TLS in Transit]
            EBS[EBS Encryption]
        end

        subgraph "Layer 5: Runtime"
            SEC[Security Context]
            CAP[Linux Capabilities]
            PSS[Pod Security Standards]
        end

        subgraph "Layer 6: Monitoring"
            CW[CloudWatch]
            DEF[Defender]
            POSTURE[Security Posture]
        end
    end

    FW --> NSG --> NP --> IAM --> WI --> SA --> SM --> KV --> GSM --> KMS --> TLS --> EBS --> SEC --> CAP --> PSS --> CW --> DEF --> POSTURE
```

## AWS ECS Architecture

```mermaid
flowchart TB
    subgraph "AWS Account"
        subgraph "VPC"
            subgraph "Availability Zone 1"
                PUB1[Public Subnet]
                PRIV1[Private Subnet]
                NAT1[NAT Gateway]
            end
            subgraph "Availability Zone 2"
                PUB2[Public Subnet]
                PRIV2[Private Subnet]
                NAT2[NAT Gateway]
            end
            IGW[Internet Gateway]
        end

        subgraph "ECS"
            CLUSTER[ECS Cluster]
            SERVICE[ECS Service]
            TASK[Task Definition]
        end

        subgraph "Security"
            SG[Security Group]
            ROLE[IAM Roles]
            KMS[KMS Keys]
        end

        subgraph "Secrets"
            SM1[Activation ID]
            SM2[Customer ID]
        end

        subgraph "Monitoring"
            CW[CloudWatch Logs]
            CI[Container Insights]
            FL[VPC Flow Logs]
        end

        subgraph "Compute"
            ASG[Auto Scaling Group]
            LT[Launch Template]
            EC2A[EC2 Instance AZ1]
            EC2B[EC2 Instance AZ2]
        end
    end

    IGW --> PUB1 & PUB2
    PUB1 --> NAT1
    PUB2 --> NAT2
    PRIV1 --> NAT1
    PRIV2 --> NAT2
    NAT1 & NAT2 -->|HTTPS| Internet

    CLUSTER --> SERVICE --> TASK
    ASG --> LT --> EC2A & EC2B
    EC2A --> PRIV1
    EC2B --> PRIV2

    TASK --> SM1 & SM2
    EC2A & EC2B --> SG
    TASK --> CW
    CLUSTER --> CI
```

## AWS EKS Architecture

```mermaid
flowchart TB
    subgraph "AWS Account"
        subgraph "VPC"
            subgraph "Availability Zone 1"
                PUB1E[Public Subnet]
                PRIV1E[Private Subnet]
                NAT1E[NAT Gateway]
            end
            subgraph "Availability Zone 2"
                PUB2E[Public Subnet]
                PRIV2E[Private Subnet]
                NAT2E[NAT Gateway]
            end
            IGWE[Internet Gateway]
        end

        subgraph "EKS"
            CLUSTER[EKS Cluster]
            NODEGROUP[Managed Node Group]
            OIDC[OIDC Provider]
        end

        subgraph "Security"
            SGE[Security Groups]
            ROLEE[IAM Roles]
            KMSE[KMS Keys]
        end

        subgraph "Monitoring"
            CWE[CloudWatch Logs]
            APILOGS[API/Audit Logs]
            FLE[VPC Flow Logs]
        end

        subgraph "Compute"
            LTE[Launch Template]
            NODE1[EKS Node AZ1]
            NODE2[EKS Node AZ2]
        end
    end

    IGWE --> PUB1E & PUB2E
    PUB1E --> NAT1E
    PUB2E --> NAT2E
    PRIV1E --> NAT1E
    PRIV2E --> NAT2E
    NAT1E & NAT2E -->|HTTPS| Internet

    CLUSTER --> NODEGROUP --> LTE --> NODE1 & NODE2
    NODE1 --> PRIV1E
    NODE2 --> PRIV2E
    CLUSTER --> OIDC
    CLUSTER --> KMSE
    CLUSTER --> CWE & APILOGS
```

## Kubernetes DaemonSet Flow

```mermaid
flowchart TB
    subgraph "Kubernetes Cluster"
        subgraph "qualys-sensor Namespace"
            NS[Namespace]
            SEC[Secret: qualys-credentials]
            SA[ServiceAccount]
            CR[ClusterRole]
            CRB[ClusterRoleBinding]
            NP[NetworkPolicy]
            RQ[ResourceQuota]
            LR[LimitRange]
            PDB[PodDisruptionBudget]
        end

        subgraph "Node 1"
            POD1[Registry Sensor Pod]
            DS1[Docker Socket]
            CS1[Containerd Socket]
        end

        subgraph "Node 2"
            POD2[Registry Sensor Pod]
            DS2[Docker Socket]
            CS2[Containerd Socket]
        end

        subgraph "Node N"
            PODN[Registry Sensor Pod]
            DSN[Docker Socket]
            CSN[Containerd Socket]
        end

        DS[DaemonSet Controller]
    end

    NS --> SEC & SA & NP & RQ & LR & PDB
    SA --> CR --> CRB
    DS --> POD1 & POD2 & PODN
    POD1 --> DS1 & CS1
    POD2 --> DS2 & CS2
    PODN --> DSN & CSN
    SEC --> POD1 & POD2 & PODN
```

## Credential Flow

```mermaid
sequenceDiagram
    participant TF as Terraform
    participant SM as Secret Store
    participant KMS as KMS/Encryption
    participant Task as Container Task
    participant Sensor as Registry Sensor
    participant QP as Qualys Platform

    TF->>KMS: Create encryption key
    TF->>SM: Store ACTIVATION_ID (encrypted)
    TF->>SM: Store CUSTOMER_ID (encrypted)

    Note over Task,Sensor: Container Startup

    Task->>SM: Request credentials
    SM->>KMS: Decrypt secrets
    KMS-->>SM: Decrypted values
    SM-->>Task: Return credentials
    Task->>Sensor: Inject as environment variables

    Sensor->>QP: Authenticate with credentials
    QP-->>Sensor: Session established

    loop Scanning Cycle
        Sensor->>Sensor: Scan container registry images
        Sensor->>QP: Report vulnerabilities
    end
```

## Network Security Flow

```mermaid
flowchart LR
    subgraph "Private Network"
        POD[Registry Sensor Pod]
    end

    subgraph "Network Policy"
        direction TB
        EGRESS[Egress Rules]
        INGRESS[Ingress Rules]
    end

    subgraph "Allowed Destinations"
        DNS[DNS - Port 53]
        QUALYS[Qualys API - Port 443]
        K8SAPI[K8s API - Port 6443]
    end

    subgraph "Blocked"
        INTERNAL[Internal IPs]
        OTHER[Other Ports]
    end

    POD --> EGRESS
    EGRESS --> DNS
    EGRESS --> QUALYS
    EGRESS --> K8SAPI
    EGRESS -.->|Blocked| INTERNAL
    EGRESS -.->|Blocked| OTHER
    INGRESS -.->|Deny All| POD
```

## Container Security Context

```mermaid
flowchart TB
    subgraph "Security Context Configuration"
        subgraph "Pod Level"
            SECC[seccompProfile: RuntimeDefault]
            HN[hostNetwork: false]
            HP[hostPID: false]
            HI[hostIPC: false]
        end

        subgraph "Container Level"
            PRIV[privileged: false]
            CAPS[Capabilities]
            RO[readOnlyRootFilesystem: false]
        end

        subgraph "Capabilities"
            DROP[DROP: ALL]
            ADD1[ADD: SYS_ADMIN]
            ADD2[ADD: DAC_OVERRIDE]
            ADD3[ADD: SETUID]
            ADD4[ADD: SETGID]
        end

        subgraph "Volume Mounts"
            DOCK[docker.sock: RW]
            CONT[containerd.sock: RW]
            DROOT[docker root: RO]
            CROOT[containerd root: RO]
        end
    end

    SECC --> PRIV
    PRIV --> CAPS
    CAPS --> DROP --> ADD1 --> ADD2 --> ADD3 --> ADD4
    ADD4 --> DOCK --> CONT --> DROOT --> CROOT
```

## Multi-Cloud Comparison

```mermaid
flowchart TB
    subgraph "Common Components"
        VPC[Virtual Private Cloud]
        NAT[NAT Gateway]
        FW[Firewall/Security Group]
        SECRETS[Secrets Management]
        LOGGING[Centralized Logging]
        SENSOR[Qualys Container Security Registry Sensor]
    end

    subgraph "AWS ECS"
        ECS[ECS Cluster]
        EC2[EC2 Instances]
        SM[Secrets Manager]
        CW[CloudWatch]
        IMDS[IMDSv2]
    end

    subgraph "AWS EKS"
        EKS[EKS Cluster]
        NODEGROUPS[Managed Node Groups]
        OIDC[OIDC Provider]
        CW2[CloudWatch]
        KMSEKS[KMS Encryption]
    end

    subgraph "Azure Specific"
        AKS[AKS Cluster]
        VMSS[VM Scale Sets]
        KV[Key Vault]
        LA[Log Analytics]
        DEF[Defender for Containers]
        WI_AZ[Workload Identity]
    end

    subgraph "GCP Specific"
        GKE[GKE Cluster]
        MIG[Managed Instance Groups]
        GSM[Secret Manager]
        CL[Cloud Logging]
        BIN[Binary Authorization]
        WI_GCP[Workload Identity]
        SHIELD[Shielded Nodes]
    end

    VPC --> AWS & Azure & GCP
    NAT --> AWS & Azure & GCP
    FW --> AWS & Azure & GCP
    SECRETS --> SM & KV & GSM
    LOGGING --> CW & LA & CL
```

## Deployment Commands

### AWS ECS
```bash
cd aws
terraform init
terraform plan
terraform apply
```

### AWS EKS
```bash
cd aws-eks
terraform init
terraform plan
terraform apply

aws eks update-kubeconfig --name qualys-registry-cluster --region us-east-1
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
```

### Azure
```bash
cd azure
terraform init
terraform plan
terraform apply

az aks get-credentials --resource-group qualys-registry-sensor-rg --name qualys-registry-cluster
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
```

### GCP
```bash
cd gcp
terraform init
terraform plan
terraform apply

gcloud container clusters get-credentials qualys-registry-cluster --region us-central1
kubectl apply -f ../kubernetes/qualys-daemonset.yaml
```

## Security Controls Summary

| Control | AWS ECS | AWS EKS | Azure AKS | GCP GKE |
|---------|---------|---------|-----------|---------|
| Secrets Management | Secrets Manager + KMS | Kubernetes Secrets + KMS | Key Vault | Secret Manager |
| Network Isolation | VPC + Private Subnets | VPC + Private Subnets | VNet + NAT Gateway | VPC + Cloud NAT |
| API Restriction | Security Groups | Security Groups + OIDC | NSG + API IP Ranges | Firewall + Master Auth Networks |
| Encryption at Rest | EBS + KMS | EBS + KMS | Ephemeral Disks | pd-ssd |
| Encryption in Transit | TLS 1.2+ | TLS 1.2+ | TLS 1.2+ | TLS 1.2+ |
| Identity | IAM Roles + IMDSv2 | IAM Roles + OIDC | Managed Identity + Workload Identity | Workload Identity |
| Logging | CloudWatch + Flow Logs | CloudWatch + API Logs | Log Analytics + Defender | Cloud Logging + Prometheus |
| Image Security | ECR Scanning | ECR Scanning | ACR + Defender | Binary Authorization |
| Runtime Security | Container Insights | Container Insights | Azure Policy | Security Posture |
| Node Security | EBS Encryption | EBS Encryption + IMDSv2 | Ephemeral OS Disks | Shielded Nodes |

## Monitoring and Observability

```mermaid
flowchart LR
    subgraph "Data Sources"
        SENSOR[Registry Sensor Logs]
        METRICS[Container Metrics]
        EVENTS[Kubernetes Events]
        FLOW[Network Flow Logs]
    end

    subgraph "Collection"
        CW[CloudWatch Agent]
        OMS[OMS Agent]
        PROM[Managed Prometheus]
    end

    subgraph "Storage"
        CWLOGS[CloudWatch Logs]
        LA[Log Analytics]
        CL[Cloud Logging]
    end

    subgraph "Analysis"
        CI[Container Insights]
        DEF[Defender Alerts]
        POSTURE[Security Posture]
    end

    subgraph "Action"
        ALERT[Alerts]
        DASH[Dashboards]
        REPORT[Reports]
    end

    SENSOR --> CW --> CWLOGS --> CI --> ALERT
    SENSOR --> OMS --> LA --> DEF --> DASH
    SENSOR --> PROM --> CL --> POSTURE --> REPORT
```

## Conclusion

This multi-cloud deployment provides a consistent, secure approach to deploying the Qualys Container Security Registry Sensor across AWS (ECS and EKS), Azure AKS, and GCP GKE. Key security features include:

- **Secrets stored in cloud-native secret managers** with KMS encryption
- **Private networking** with NAT gateways for outbound-only access
- **Network policies** restricting pod communication
- **Workload identity** for secure cloud API access
- **Comprehensive logging** and monitoring
- **Binary authorization** (GCP) for image verification
- **Defender for Containers** (Azure) for threat detection
- **Container Insights** (AWS) for performance monitoring
- **OIDC provider** (EKS) for IAM Roles for Service Accounts

All configurations follow CIS Benchmarks and cloud provider security best practices.
