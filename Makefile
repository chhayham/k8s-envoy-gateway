# k8s-envoy-gateway Makefile
# Bootstrap script runner for minikube cluster and ArgoCD setup

.PHONY: help setup clean reset
# Default target
help:
	@echo "k8s-envoy-gateway - Kubernetes Envoy Gateway Demo"
	@echo ""
	@echo "Available targets:"
	@echo "  setup             - Bootstrap the minikube cluster and install ArgoCD"
	@echo "  clean             - Delete the minikube cluster"
	@echo "  reset             - Recreate minikube cluster"
	@echo "  help              - Show this help message"

# Run the setup script to bootstrap the cluster and ArgoCD
setup:
	@echo "🚀 Running setup script..."
	@chmod +x scripts/setup.sh
	@scripts/setup.sh

# Delete the minikube cluster
clean:
	@echo "🗑️  Deleting minikube cluster 'demo'..."
	@minikube delete -p demo || echo "Cluster 'demo' does not exist"

# Recreate minikube cluster
reset:
	@echo "🔄  Recreating minikube cluster 'demo'..."
	$(MAKE) clean
	$(MAKE) setup