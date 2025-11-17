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
  description = "Name of the VM Scale Set"
  type        = string
  default     = "qualys-registry-cluster"
}

variable "instance_count" {
  description = "Number of VM instances"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for instances"
  type        = string
  default     = "Standard_D2s_v3"
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

variable "qualys_image" {
  description = "Qualys container sensor image"
  type        = string
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

variable "qualys_https_proxy" {
  description = "HTTPS proxy server (FQDN or IP:port)"
  type        = string
  default     = ""
}

variable "https_proxy" {
  description = "Standard HTTPS proxy environment variable"
  type        = string
  default     = ""
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Production"
    Purpose     = "Qualys Registry Sensor"
  }
}

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

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_network_security_group" "vmss" {
  name                = "${var.cluster_name}-vmss-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTPSOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Allow HTTPS for Qualys platform and ACR"
  }

  security_rule {
    name                       = "AllowDNSOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Allow DNS queries"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny all inbound traffic"
  }

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_subnet" "vmss_subnet" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.0.0/20"]
}

resource "azurerm_subnet_network_security_group_association" "vmss" {
  subnet_id                 = azurerm_subnet.vmss_subnet.id
  network_security_group_id = azurerm_network_security_group.vmss.id
}

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

resource "azurerm_nat_gateway" "nat" {
  name                = "${var.cluster_name}-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "vmss" {
  subnet_id      = azurerm_subnet.vmss_subnet.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

resource "azurerm_user_assigned_identity" "vmss" {
  name                = "QualysRegistrySensorVMSS-Identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "vmss_acr" {
  count                = var.create_acr ? 1 : 0
  principal_id         = azurerm_user_assigned_identity.vmss.principal_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr[0].id
}

locals {
  env_vars = join(" ", concat(
    [
      "-e ACTIVATIONID='${var.qualys_activation_id}'",
      "-e CUSTOMERID='${var.qualys_customer_id}'"
    ],
    var.qualys_pod_url != "" ? ["-e POD_URL='${var.qualys_pod_url}'"] : [],
    var.qualys_https_proxy != "" ? ["-e qualys_https_proxy='${var.qualys_https_proxy}'"] : [],
    var.https_proxy != "" ? ["-e https_proxy='${var.https_proxy}'"] : []
  ))

  custom_data = base64encode(<<-EOF
#!/bin/bash
set -e

apt-get update
apt-get install -y docker.io jq

systemctl start docker
systemctl enable docker

mkdir -p /var/qualys/qpa/data/cert

${var.create_acr ? "az login --identity --username ${azurerm_user_assigned_identity.vmss.client_id}" : ""}
${var.create_acr ? "TOKEN=$(az acr login --name ${azurerm_container_registry.acr[0].name} --expose-token --output tsv --query accessToken)" : ""}
${var.create_acr ? "docker login ${azurerm_container_registry.acr[0].login_server} -u 00000000-0000-0000-0000-000000000000 -p $TOKEN" : ""}

docker run -d --restart=always \
  --name qualys-container-sensor \
  --privileged \
  --net=host \
  ${local.env_vars} \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/qualys/qpa/data/cert:/usr/local/qualys/qpa/data/cert \
  ${var.qualys_image}
EOF
  )
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "${var.cluster_name}-vmss"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.vm_size
  instances           = var.instance_count
  admin_username      = "qualysadmin"
  upgrade_mode        = "Manual"

  admin_ssh_key {
    username   = "qualysadmin"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0g+ZgQHQo placeholder-key"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  network_interface {
    name                      = "vmss-nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.vmss.id

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.vmss_subnet.id
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vmss.id]
  }

  custom_data = local.custom_data

  tags = {
    Environment = "Production"
    Purpose     = "Qualys Registry Sensor"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.vmss,
    azurerm_subnet_network_security_group_association.vmss,
    azurerm_role_assignment.vmss_acr
  ]
}

output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Name of the resource group"
}

output "vmss_name" {
  value       = azurerm_linux_virtual_machine_scale_set.vmss.name
  description = "Name of the VM Scale Set"
}

output "vmss_id" {
  value       = azurerm_linux_virtual_machine_scale_set.vmss.id
  description = "ID of the VM Scale Set"
}

output "acr_login_server" {
  value       = var.create_acr ? azurerm_container_registry.acr[0].login_server : ""
  description = "Login server for Azure Container Registry"
}

output "qualys_image_location" {
  value       = var.create_acr ? "${azurerm_container_registry.acr[0].login_server}/qualys/qcs-sensor:latest" : var.qualys_image
  description = "Expected location of Qualys container image"
}
