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

variable "zone" {
  description = "GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the managed instance group"
  type        = string
  default     = "qualys-registry-cluster"
}

variable "instance_count" {
  description = "Number of VM instances"
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Machine type for instances"
  type        = string
  default     = "e2-standard-2"
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

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

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

resource "google_compute_firewall" "internal" {
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

  source_ranges = [var.subnet_cidr]
  target_tags   = ["qualys-registry-sensor"]
}

resource "google_compute_firewall" "https_egress" {
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

resource "google_service_account" "mig_sa" {
  account_id   = "qualys-registry-sensor-mig-sa"
  display_name = "Qualys Registry Sensor MIG Service Account"
}

resource "google_project_iam_member" "mig_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

resource "google_project_iam_member" "mig_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

resource "google_project_iam_member" "mig_sa_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

locals {
  env_vars = {
    ACTIVATIONID       = var.qualys_activation_id
    CUSTOMERID         = var.qualys_customer_id
    POD_URL            = var.qualys_pod_url
    qualys_https_proxy = var.qualys_https_proxy
    https_proxy        = var.https_proxy
  }

  env_string = join(",", [
    for k, v in local.env_vars : "${k}=${v}" if v != ""
  ])

  container_declaration = {
    spec = {
      containers = [{
        name  = "qualys-container-sensor"
        image = var.qualys_image
        env = [
          for k, v in local.env_vars : {
            name  = k
            value = v
          } if v != ""
        ]
        securityContext = {
          privileged = true
        }
        volumeMounts = [
          {
            name      = "docker-sock"
            mountPath = "/var/run/docker.sock"
          },
          {
            name      = "persistent-volume"
            mountPath = "/usr/local/qualys/qpa/data/cert"
          }
        ]
      }]
      volumes = [
        {
          name = "docker-sock"
          hostPath = {
            path = "/var/run/docker.sock"
          }
        },
        {
          name = "persistent-volume"
          hostPath = {
            path = "/var/qualys/qpa/data/cert"
          }
        }
      ]
      restartPolicy = "Always"
    }
  }
}

resource "google_compute_instance_template" "qualys" {
  name_prefix  = "${var.cluster_name}-"
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = "cos-cloud/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
  }

  service_account {
    email  = google_service_account.mig_sa.email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  metadata = {
    gce-container-declaration = jsonencode(local.container_declaration)
    google-logging-enabled    = "true"
  }

  tags = ["qualys-registry-sensor"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "qualys" {
  name               = "${var.cluster_name}-mig"
  base_instance_name = "${var.cluster_name}-instance"
  zone               = var.zone
  target_size        = var.instance_count

  version {
    instance_template = google_compute_instance_template.qualys.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing.id
    initial_delay_sec = 300
  }
}

resource "google_compute_health_check" "autohealing" {
  name                = "${var.cluster_name}-health-check"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 22
  }
}

output "project_id" {
  value       = var.project_id
  description = "GCP Project ID"
}

output "region" {
  value       = var.region
  description = "GCP region"
}

output "mig_name" {
  value       = google_compute_instance_group_manager.qualys.name
  description = "Managed Instance Group name"
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "VPC network name"
}

output "subnet_name" {
  value       = google_compute_subnetwork.subnet.name
  description = "Subnet name"
}

output "qualys_image_location" {
  value       = "gcr.io/${var.project_id}/qualys/qcs-sensor:latest"
  description = "Expected location of Qualys container image in GCR"
}
