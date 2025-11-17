region = "us-east-1"

cluster_name = "qualys-registry-cluster"

instance_type    = "c5.large"
min_size         = 1
max_size         = 3
desired_capacity = 2

create_vpc = false
vpc_id     = ""
subnet_ids = []

key_name = ""

qualys_image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/qualys/qcs-sensor:latest"
qualys_activation_id = "YOUR_ACTIVATION_ID"
qualys_customer_id   = "YOUR_CUSTOMER_ID"
qualys_pod_url       = "https://qualysapi.qualys.com"

qualys_https_proxy = ""
https_proxy        = ""
