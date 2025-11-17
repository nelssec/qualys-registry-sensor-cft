terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "qualys-registry-cluster"
}

variable "node_count" {
  description = "Number of nodes per zone"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Machine type for cluster nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "create_gcr" {
  description = "Enable Google Container Registry for Qualys images"
  type        = bool
  default     = true
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
  description = "Qualys container sensor image"
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "qualys-registry-network"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "qualys-registry-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/20"
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for outbound internet access
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rule for GKE internal traffic
resource "google_compute_firewall" "gke_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    "10.1.0.0/16",
    "10.2.0.0/16",
  ]

  target_tags = ["qualys-registry-sensor"]
}

# Firewall rule for HTTPS egress
resource "google_compute_firewall" "qualys_egress" {
  name      = "${var.cluster_name}-allow-https-egress"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["qualys-registry-sensor"]
}

# Firewall rule for DNS egress
resource "google_compute_firewall" "dns_egress" {
  name      = "${var.cluster_name}-allow-dns-egress"
  network   = google_compute_network.vpc.name
  direction = "EGRESS"

  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["qualys-registry-sensor"]
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Regional cluster with multiple zones
  node_locations = [
    "${var.region}-a",
    "${var.region}-b",
  ]

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.3.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Release channel for automatic updates
  release_channel {
    channel = "REGULAR"
  }

  # Security settings
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Network policy
  network_policy {
    enabled = true
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = var.machine_type

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      environment = "production"
      purpose     = "qualys-registry-sensor"
    }

    tags = ["qualys-registry-sensor"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# Service Account for GKE nodes
resource "google_service_account" "gke_sa" {
  account_id   = "qualys-registry-sensor-gke-sa"
  display_name = "Qualys Registry Sensor GKE Node Service Account"
}

# IAM bindings for the service account
resource "google_project_iam_member" "gke_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_project_iam_member" "gke_sa_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Enable required APIs
resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Kubernetes provider configuration
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Kubernetes namespace
resource "kubernetes_namespace" "qualys_sensor" {
  metadata {
    name = "qualys-sensor"
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes secret for Qualys credentials
resource "kubernetes_secret" "qualys_credentials" {
  metadata {
    name      = "qualys-credentials"
    namespace = kubernetes_namespace.qualys_sensor.metadata[0].name
  }

  data = {
    activation-id = var.qualys_activation_id
    customer-id   = var.qualys_customer_id
    pod-url       = var.qualys_pod_url
  }

  type = "Opaque"
}

# Outputs
output "project_id" {
  value       = var.project_id
  description = "GCP Project ID"
}

output "region" {
  value       = var.region
  description = "GCP region"
}

output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE cluster name"
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE cluster endpoint"
  sensitive   = true
}

output "get_credentials_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
  description = "Command to get GKE credentials"
}

output "qualys_image_location" {
  value       = var.qualys_image != "" ? var.qualys_image : "gcr.io/${var.project_id}/qualys/qcs-sensor:latest"
  description = "Expected location of Qualys container image"
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "VPC network name"
}

output "subnet_name" {
  value       = google_compute_subnetwork.subnet.name
  description = "Subnet name"
}
