.PHONY: help init-aws init-azure init-gcp plan-aws plan-azure plan-gcp deploy-aws deploy-azure deploy-gcp destroy-aws destroy-azure destroy-gcp deploy-k8s-azure deploy-k8s-gcp validate clean logs-aws logs-azure logs-gcp status-aws status-azure status-gcp

help:
	@echo "Qualys Container Security Registry Sensor"
	@echo ""
	@echo "Setup:"
	@echo "  make init-aws          Initialize AWS Terraform"
	@echo "  make init-azure        Initialize Azure Terraform"
	@echo "  make init-gcp          Initialize GCP Terraform"
	@echo ""
	@echo "Plan:"
	@echo "  make plan-aws          Plan AWS deployment"
	@echo "  make plan-azure        Plan Azure deployment"
	@echo "  make plan-gcp          Plan GCP deployment"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy-aws        Deploy to AWS ECS"
	@echo "  make deploy-azure      Deploy to Azure AKS"
	@echo "  make deploy-gcp        Deploy to GCP GKE"
	@echo ""
	@echo "Status:"
	@echo "  make status-aws        Check AWS ECS status"
	@echo "  make status-azure      Check Azure AKS status"
	@echo "  make status-gcp        Check GCP GKE status"
	@echo ""
	@echo "Logs:"
	@echo "  make logs-aws          View AWS logs"
	@echo "  make logs-azure        View Azure logs"
	@echo "  make logs-gcp          View GCP logs"
	@echo ""
	@echo "Destroy:"
	@echo "  make destroy-aws       Destroy AWS infrastructure"
	@echo "  make destroy-azure     Destroy Azure infrastructure"
	@echo "  make destroy-gcp       Destroy GCP infrastructure"
	@echo ""
	@echo "Utilities:"
	@echo "  make validate          Validate all configurations"
	@echo "  make clean             Clean Terraform cache"

init-aws:
	@cd aws && terraform init

init-azure:
	@cd azure && terraform init

init-gcp:
	@cd gcp && terraform init

plan-aws: init-aws
	@cd aws && terraform plan

plan-azure: init-azure
	@cd azure && terraform plan

plan-gcp: init-gcp
	@cd gcp && terraform plan

deploy-aws: init-aws
	@cd aws && terraform apply
	@echo ""
	@echo "AWS deployment complete."

deploy-k8s-azure:
	@$$(cd azure && terraform output -raw get_credentials_command)
	@kubectl apply -f kubernetes/qualys-daemonset.yaml
	@kubectl wait --for=condition=ready pod -l app=qualys-container-sensor -n qualys-sensor --timeout=300s || true
	@kubectl get pods -n qualys-sensor

deploy-azure: init-azure
	@cd azure && terraform apply
	@$(MAKE) deploy-k8s-azure
	@echo ""
	@echo "Azure deployment complete."

deploy-k8s-gcp:
	@$$(cd gcp && terraform output -raw get_credentials_command)
	@kubectl apply -f kubernetes/qualys-daemonset.yaml
	@kubectl wait --for=condition=ready pod -l app=qualys-container-sensor -n qualys-sensor --timeout=300s || true
	@kubectl get pods -n qualys-sensor

deploy-gcp: init-gcp
	@cd gcp && terraform apply
	@$(MAKE) deploy-k8s-gcp
	@echo ""
	@echo "GCP deployment complete."

destroy-aws:
	@cd aws && terraform destroy

destroy-azure:
	@kubectl delete -f kubernetes/qualys-daemonset.yaml --ignore-not-found || true
	@cd azure && terraform destroy

destroy-gcp:
	@kubectl delete -f kubernetes/qualys-daemonset.yaml --ignore-not-found || true
	@cd gcp && terraform destroy

validate:
	@echo "Validating configurations..."
	@cd aws && terraform init -backend=false > /dev/null && terraform validate
	@cd azure && terraform init -backend=false > /dev/null && terraform validate
	@cd gcp && terraform init -backend=false > /dev/null && terraform validate
	@echo "All configurations valid."

clean:
	@rm -rf aws/.terraform aws/.terraform.lock.hcl
	@rm -rf azure/.terraform azure/.terraform.lock.hcl
	@rm -rf gcp/.terraform gcp/.terraform.lock.hcl
	@echo "Clean complete."

logs-aws:
	@aws logs tail /ecs/$$(cd aws && terraform output -raw cluster_name)/qualys-sensor --follow

logs-azure:
	@kubectl logs -n qualys-sensor -l app=qualys-container-sensor -f

logs-gcp:
	@kubectl logs -n qualys-sensor -l app=qualys-container-sensor -f

status-aws:
	@aws ecs describe-services --cluster $$(cd aws && terraform output -raw cluster_name) --services $$(cd aws && terraform output -raw service_name) --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' --output table

status-azure:
	@kubectl get pods -n qualys-sensor -o wide

status-gcp:
	@kubectl get pods -n qualys-sensor -o wide
