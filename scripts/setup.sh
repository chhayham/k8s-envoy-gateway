#!/bin/bash
# Idempotent script for ArgoCD bootstrap
# This script deploys ArgoCD and sets up the ApplicationSet

set -e  # Fail fast on errors

echo "=== Checking prerequisites ==="

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed or not in PATH"
    exit 1
fi

echo "✓ podman found: $(podman --version)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

echo "✓ kubectl found: $(kubectl version --client --short 2>/dev/null || echo 'version unknown')"

# Check if minikube is available
if ! command -v minikube &> /dev/null; then
    echo "ERROR: minikube is not installed or not in PATH"
    exit 1
fi

echo "✓ minikube found: $(minikube version | grep version | head -1)"

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed or not in PATH"
    exit 1
fi

echo "✓ helm found: $(helm version --short)"

# Check if minikube cluster exists
MINIKUBE_EXISTS=false
if minikube status -p demo &> /dev/null; then
    MINIKUBE_EXISTS=true
fi

# Set namespace
NAMESPACE="argocd"

echo ""
echo "=== Setting up Minikube Cluster ==="

if [ "$MINIKUBE_EXISTS" = "true" ]; then
    echo "Minikube cluster 'demo' already exists. Starting it..."
    minikube start -p demo --driver=podman
else
    echo "Creating new Minikube cluster 'demo' with 3 nodes..."
    minikube start -p demo --driver=podman --nodes=3
fi

# Configure kubectl to use minikube
# kubectl config use-context demo

echo "✓ Minikube cluster ready"
echo ""

echo "=== Deploying ArgoCD ==="

# Create namespace if it doesn't exist
echo "Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install Gateway API CRDs if not already installed
# if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
#     echo "Installing Gateway API CRDs..."
#     kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml?raw=true
# fi

# echo "✓ Gateway API CRDs ready"


# Install KEDA CRDs

kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.21.0/keda-2.21.0-crds.yaml?raw=true

# Deploy ArgoCD using Helm
echo "Deploying ArgoCD via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm upgrade --install argocd argo/argo-cd \
    --version 10.9.2 \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f deploy/argocd/values.yaml \
    --wait

echo "✓ ArgoCD deployed"

echo ""
echo "=== Setting up ApplicationSet ==="

# Check if ApplicationSet exists and decide whether to edit or apply
if kubectl get applicationsets.argoproj.io cluster-addons -n "$NAMESPACE" --no-headers &> /dev/null; then
    echo "ApplicationSet 'cluster-addons' already exists in namespace '$NAMESPACE'"
    # echo "Opening editor to modify the ApplicationSet..."
    # kubectl edit applicationsets.argoproj.io cluster-addons -n "$NAMESPACE"
else
    echo "ApplicationSet 'cluster-addons' not found - creating from manifest..."
    kubectl apply -f deploy/argocd-applicationsets/root.yaml
fi

echo ""
echo "=== Installing Argo Rollouts ==="

# Deploy Argo Rollouts using Helm
ROLLOUTS_NS="argo-rollouts"
echo "Ensuring namespace '$ROLLOUTS_NS' exists..."
kubectl create namespace "$ROLLOUTS_NS" --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying Argo Rollouts via Helm..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
    --version 2.40.6 \
    --namespace "$ROLLOUTS_NS" \
    --create-namespace \
    --wait

echo "✓ Argo Rollouts installed"

# Wait for ArgoCD components to be ready
echo "Checking ArgoCD pod status..."
kubectl -n "$NAMESPACE" wait --for=condition=Ready pods --timeout=120s --all 2>/dev/null || echo "Warning: Some pods may not be ready yet"

echo ""
echo "ApplicationSet status:"
kubectl get applicationsets.argoproj.io cluster-addons -n "$NAMESPACE" -o wide

echo ""
echo "=== Setup Complete ==="
echo "ArgoCD is running in namespace '$NAMESPACE'"
echo "Argo Rollouts is running in namespace '$ROLLOUTS_NS'"
echo "ApplicationSet 'cluster-addons' has been configured"
echo ""
echo "Access the ArgoCD dashboard at: http://argocd.localhost"
echo "Username: admin"
echo "Password: admin"
