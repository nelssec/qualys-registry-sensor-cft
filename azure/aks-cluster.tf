terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "qualys-registry-sensor-rg"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "qualys-registry-cluster"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for cluster nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "create_acr" {
  description = "Create Azure Container Registry for Qualys images"
  type        = bool
  default     = true
}

variable "acr_name" {
  description = "Name of the Azure Container Registry (must be globally unique)"
  type        = string
  default     = ""
}

variable "qualys_activation_id" {
  description = "Qualys activation ID"
  type        = string
  sensitive   = true
}

variable "qualys_customer_id" {
  description = "Qualys customer ID"
  type        = string
  sensitive   = true
}

variable "qualys_pod_url" {
  description = "Qualys Container Security Server URL"
  type        = string
}

variable "qualys_image" {
  description = "Qualys container sensor image (will use ACR if created)"
  type        = string
  default     = ""
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Production"
    Purpose     = "Qualys Registry Sensor"
  }
}

# Azure Container Registry (optional)
resource "azurerm_container_registry" "acr" {
  count               = var.create_acr ? 1 : 0
  name                = var.acr_name != "" ? var.acr_name : replace("${var.cluster_name}acr", "-", "")
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = false

  tags = {
    Environment = "Production"
    Purpose     = "Qualys Container Images"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = "Production"
  }
}

# Subnet for AKS
resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.0.0/20"]
}

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat" {
  name                = "${var.cluster_name}-nat-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = "Production"
  }
}

# NAT Gateway for outbound internet access
resource "azurerm_nat_gateway" "nat" {
  name                = "${var.cluster_name}-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"

  tags = {
    Environment = "Production"
  }
}

# Associate NAT Gateway with Public IP
resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with AKS Subnet
resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks_subnet.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    type                = "VirtualMachineScaleSets"
    os_disk_size_gb     = 30
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 10

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
    service_cidr      = "10.2.0.0/16"
    dns_service_ip    = "10.2.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  }

  tags = {
    Environment = "Production"
    Purpose     = "Qualys Registry Sensor"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.aks
  ]
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = "Production"
  }
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr" {
  count                = var.create_acr ? 1 : 0
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr[0].id
}

# Kubernetes Secret for Qualys credentials
resource "null_resource" "qualys_secret" {
  depends_on = [azurerm_kubernetes_cluster.aks]

  provisioner "local-exec" {
    command = <<-EOT
      az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing
      kubectl create namespace qualys-sensor --dry-run=client -o yaml | kubectl apply -f -
      kubectl create secret generic qualys-credentials \
        --namespace qualys-sensor \
        --from-literal=activation-id='${var.qualys_activation_id}' \
        --from-literal=customer-id='${var.qualys_customer_id}' \
        --from-literal=pod-url='${var.qualys_pod_url}' \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.aks.id
  }
}

# Outputs
output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Name of the resource group"
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "Name of the AKS cluster"
}

output "aks_cluster_id" {
  value       = azurerm_kubernetes_cluster.aks.id
  description = "ID of the AKS cluster"
}

output "acr_login_server" {
  value       = var.create_acr ? azurerm_container_registry.acr[0].login_server : ""
  description = "Login server for Azure Container Registry"
}

output "get_credentials_command" {
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
  description = "Command to get AKS credentials"
}

output "qualys_image_location" {
  value       = var.create_acr ? "${azurerm_container_registry.acr[0].login_server}/qualys/qcs-sensor:latest" : var.qualys_image
  description = "Expected location of Qualys container image"
}
