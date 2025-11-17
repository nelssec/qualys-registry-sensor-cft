project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

cluster_name   = "qualys-registry-cluster"
instance_count = 2
machine_type   = "e2-standard-2"

network_name = "qualys-registry-network"
subnet_name  = "qualys-registry-subnet"
subnet_cidr  = "10.0.0.0/20"

qualys_image         = "gcr.io/your-gcp-project-id/qualys/qcs-sensor:latest"
qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"

qualys_https_proxy = ""
https_proxy        = ""
