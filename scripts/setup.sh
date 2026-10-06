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

echo ""
echo "=== Setting up Minikube Cluster ==="

if [ "$MINIKUBE_EXISTS" = "true" ]; then
    echo "Minikube cluster 'demo' already exists. Starting it..."
    minikube start -p demo --driver=podman
else
    echo "Creating new Minikube cluster 'demo' with 3 nodes..."
    minikube start -p demo --driver=podman --nodes=3
fi

echo "✓ Minikube cluster ready"

# Template Calico CRDs and install CRDs
CALICO_CRDS_VERSION=v3.33.0
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm repo update
kubectl create namespace tigera-operator --dry-run=client -o yaml | kubectl apply -f -
# helm template calico-crds projectcalico/projectcalico.org.v3 --version $CALICO_CRDS_VERSION --api-versions admissionregistration.k8s.io/v1beta1/MutatingAdmissionPolicy --output-dir deploy/argocd-applications/calico/crds
helm template calico-crds projectcalico/projectcalico.org.v3 --version $CALICO_CRDS_VERSION --api-versions admissionregistration.k8s.io/v1/MutatingAdmissionPolicy | kubectl apply --server-side -f -
# Install KEDA CRDs
echo ""
echo "=== Deploying KEDA CRDs ==="
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.21.0/keda-2.21.0-crds.yaml?raw=true

echo ""
echo "=== Deploying ArgoCD ==="
# Deploy ArgoCD using Helm
ARGO_NS="argocd"
echo "Deploying ArgoCD via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm upgrade --install argocd argo/argo-cd \
    --version 10.9.2 \
    --namespace "$ARGO_NS" \
    --create-namespace \
    -f deploy/argocd/values.yaml \
    --wait

echo "✓ ArgoCD deployed"

echo ""
echo "=== Setting up ApplicationSet ==="

# Check if ApplicationSet exists and decide whether to edit or apply
if kubectl get applicationsets.argoproj.io cluster-addons -n "$ARGO_NS" --no-headers &> /dev/null; then
    echo "ApplicationSet 'cluster-addons' already exists in namespace '$ARGO_NS'"
else
    echo "ApplicationSet 'cluster-addons' not found - creating from manifest..."
    kubectl apply -f deploy/argocd-applicationsets/root.yaml
fi

# Wait for ArgoCD components to be ready
echo "Checking ArgoCD pod status..."
kubectl -n "$ARGO_NS" wait --for=condition=Ready pods --timeout=120s --all 2>/dev/null || echo "Warning: Some pods may not be ready yet"

echo ""
echo "ApplicationSet status:"
kubectl get applicationsets.argoproj.io cluster-addons -n "$ARGO_NS" -o wide

echo ""
echo "=== Setup Complete ==="
echo "ArgoCD is running in namespace '$ARGO_NS'"
echo "ApplicationSet 'cluster-addons' has been configured"
echo ""
echo "Access the ArgoCD dashboard at: http://argocd.localhost"
echo "Username: admin"
echo "Password: admin" 
echo "run 'sudo minikube tunnel -p demo' to enable traffic to envoy-gateway"