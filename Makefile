# k8s-envoy-gateway Makefile
# Bootstrap: minikube cluster + Terraform-managed platform + ArgoCD apps

TF_DIR  := terraform
TF_PLAN := plan/terraform.tfplan
TF_BASE_PLAN := plan/base.tfplan
KC_PF   := scripts/keycloak-port-forward.sh

.PHONY: help setup clean reset tf-init tf-base-plan tf-base-apply tf-plan tf-apply tf-destroy
# Default target
help:
	@echo "k8s-envoy-gateway - Kubernetes Envoy Gateway Demo (Terraform bootstrap)"
	@echo ""
	@echo "Available targets:"
	@echo "  setup          - Bootstrap minikube + Terraform platform + ArgoCD apps"
	@echo "  tf-init        - terraform init"
	@echo "  tf-base-plan   - plan the base chain (-> module.keycloak); FRESH clusters only"
	@echo "  tf-base-apply  - apply the base plan (brings Keycloak up)"
	@echo "  tf-plan        - terraform plan -> terraform/plan/terraform.tfplan"
	@echo "  tf-apply       - terraform apply of the saved plan file"
	@echo "  tf-destroy     - terraform destroy (interactive confirmation)"
	@echo "  clean          - Delete the minikube cluster"
	@echo "  reset          - Recreate the minikube cluster and re-run setup"
	@echo "  help           - Show this help message"

# Run the setup script to bootstrap the cluster, Terraform platform and ArgoCD
setup:
	@echo "🚀 Running setup script..."
	@chmod +x scripts/setup.sh
	@scripts/setup.sh

# Terraform: initialize providers/backend
tf-init:
	@cd $(TF_DIR) && mkdir -p state plan && terraform init -input=false

# Terraform: plan only the base module chain (gateway-api -> cert-manager ->
# envoy-gateway -> keycloak). The keycloak provider resources are pruned by
# -target, so NO Keycloak port-forward is needed — this is what makes a FRESH
# cluster bootstrap possible: the full plan logs into Keycloak, but the
# keycloak service does not exist until this base plan has been applied.
tf-base-plan: tf-init
	@cd $(TF_DIR) && terraform plan -input=false -target=module.keycloak -out=$(TF_BASE_PLAN)

# Terraform: apply the previously saved base plan file
tf-base-apply:
	@cd $(TF_DIR) && test -f $(TF_BASE_PLAN) || { echo "No base plan file found. Run 'make tf-base-plan' first."; exit 1; }
	@cd $(TF_DIR) && terraform apply -input=false $(TF_BASE_PLAN)

# Terraform: write the plan to a file. A localhost port-forward to Keycloak
# is started/stopped automatically for the keycloak provider (terraform/keycloak-sso.tf).
tf-plan: tf-init
	@cd $(TF_DIR) && sh -c 'bash ../$(KC_PF) start; terraform plan -input=false -out=$(TF_PLAN); rc=$$?; bash ../$(KC_PF) stop; exit $$rc'

# Terraform: apply the previously saved plan file (port-forward handled as above)
tf-apply:
	@cd $(TF_DIR) && test -f $(TF_PLAN) || { echo "No plan file found. Run 'make tf-plan' first."; exit 1; }
	@cd $(TF_DIR) && sh -c 'bash ../$(KC_PF) start; terraform apply -input=false $(TF_PLAN); rc=$$?; bash ../$(KC_PF) stop; exit $$rc'

# Terraform: destroy (asks for confirmation). The keycloak provider must log
# in while the Keycloak it manages is still running, so the port-forward is
# started/stopped around the destroy (SSO objects are destroyed before the
# keycloak module via the null_resource.keycloak_ready gate).
tf-destroy: tf-init
	@cd $(TF_DIR) && sh -c 'bash ../$(KC_PF) start; terraform destroy -input=false; rc=$$?; bash ../$(KC_PF) stop; exit $$rc'

# Delete the minikube cluster
clean:
	@echo "🗑️  Deleting minikube cluster 'demo'..."
	@minikube delete -p demo || echo "Cluster 'demo' does not exist"

# Recreate minikube cluster (full re-bootstrap: fresh cluster + fresh state)
reset:
	@echo "🔄  Recreating minikube cluster 'demo'..."
	$(MAKE) clean
	rm -rf $(TF_DIR)/state $(TF_DIR)/plan
	$(MAKE) setup
