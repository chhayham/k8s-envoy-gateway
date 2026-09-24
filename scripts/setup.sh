#!/bin/bash
set -euo pipefail

# k8s-envoy-gateway setup script
# Idempotent script to bootstrap the cluster and ArgoCD

# Check prerequisites
if ! command -v podman &> /dev/null; then
  echo "❌ Podman is required but not installed. Please install Podman first."
  exit 1
fi

if ! command -v kind &> /dev/null; then
  echo "❌ Kind is required but not installed. Please install Kind first."
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl is required but not installed. Please install kubectl first."
  exit 1
fi

# Create kind cluster if it doesn't exist
CLUSTER_NAME="envoy-demo"
if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
  echo "🚀 Creating kind cluster '$CLUSTER_NAME' with multi-node config..."
  kind create cluster --name "$CLUSTER_NAME" --config kind/kind-config.yaml
else
  echo "✅ Kind cluster '$CLUSTER_NAME' already exists."
fi

# Apply Gateway API CRDs
echo "📋 Applying Gateway API CRDs..."
kubectl apply -f deploy/gateway-api-crd/

# Verify Gateway API CRDs are installed
echo "✅ Verifying Gateway API CRDs..."
if kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io gatewayclasses.gateway.networking.k8s.io &> /dev/null; then
  echo "✅ Gateway API CRDs installed."
else
  echo "❌ Gateway API CRDs not found. Exiting."
  exit 1
fi

# Install ArgoCD
echo "📦 Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo add gateway https://envoyproxy.github.io/gateway-helm
helm repo update

# Install ArgoCD with base values
helm install argocd argo-cd/argo-cd -n argocd --create-namespace -f deploy/argocd/values.yaml --wait --timeout 5m

# Verify ArgoCD pods are running
echo "✅ Verifying ArgoCD pods..."
if kubectl -n argocd wait --for=condition=Ready --timeout=5m pods -l app.kubernetes.io/name=argocd-server; then
  echo "✅ ArgoCD is Ready."
else
  echo "❌ ArgoCD pods not ready. Check logs: kubectl -n argocd logs deploy/argocd-server"
  exit 1
fi

# Apply HTTPRoute values for ArgoCD dashboard (step 4)
echo "🌐 Exposing ArgoCD dashboard via Envoy Gateway (server.httproute)..."
helm upgrade argocd argo-cd/argo-cd -n argocd -f deploy/argocd/httproute-values.yaml --wait --timeout 5m

# Verify HTTPRoute is created
echo "✅ Verifying ArgoCD HTTPRoute..."
if kubectl -n argocd get httproute argocd-server-http-route &> /dev/null; then
  echo "✅ ArgoCD HTTPRoute created."
else
  echo "⚠️  ArgoCD HTTPRoute not yet created (Envoy Gateway may not be synced yet)."
fi

# Output ArgoCD admin password (default is 'admin' — random initially)
echo "✅ ArgoCD installation complete."
echo "📌 ArgoCD server is running in the 'argocd' namespace."
echo "📌 To access the UI, use port-forward: kubectl -n argocd port-forward svc/argocd-server 8080:443"
