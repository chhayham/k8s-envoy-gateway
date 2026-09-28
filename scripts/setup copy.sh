#!/bin/bash
set -euo pipefail

# Validate required tools
for cmd in minikube kubectl helm; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

argo_cd_chart_version=10.9.2

minikube start --profile=demo --driver=podman --nodes=3 --cpus=4 --memory=8g

# Manually install Gateway API CRDs
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml?raw=true"

helm repo add argo https://argoproj.github.io/argo-helm
# helm repo update

# helm v3 syntax
helm upgrade --install argocd argo/argo-cd \
  --version $argo_cd_chart_version \
  --namespace argocd \
  --create-namespace \
  -f deploy/argocd/values.yaml \
  --wait

# Ensure namespace exists (redundant but safe)
kubectl create namespace envoy --dry-run=client -o yaml | kubectl apply -f -

# Deploy Envoy Gateway CRDs via ArgoCD
echo "Deploying Envoy Gateway CRDs..."
kubectl apply -f deploy/argocd-applications/envoy-gateway-crds-app.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy Envoy Gateway directly via kubectl (not via ArgoCD to avoid OCI auth issues)
kubectl apply -f deploy/argocd-applications/envoy-gateway-app.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy Envoy GatewayClass and Gateway
kubectl apply -f deploy/envoy/envoy-gateway.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy Gateway API resources for Envoy Gateway
# echo "Deploying Gateway API resources for Envoy Gateway..."
# kubectl apply -f deploy/gateway-api/envoy-gateway-routes.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy ArgoCD Applications for monitoring stack
echo "Deploying cert-manager..."
kubectl apply -f deploy/argocd-applications/cert-manager-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying kube-prometheus-stack..."
kubectl apply -f deploy/argocd-applications/kube-prometheus-stack-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying loki..."
kubectl apply -f deploy/argocd-applications/loki-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying fluent-bit..."
kubectl apply -f deploy/argocd-applications/fluent-bit-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying argo-rollouts..."
kubectl apply -f deploy/argocd-applications/argo-rollouts-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying keda..."
kubectl apply -f deploy/argocd-applications/keda-app.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy ArgoCD Applications for authentication
echo "Deploying kargo..."
kubectl apply -f deploy/argocd-applications/kargo-app.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying openunison..."
kubectl apply -f deploy/argocd-applications/openunison-app.yaml --dry-run=client -o yaml | kubectl apply -f -

# Deploy Gateway API resources for all applications
echo "Deploying Gateway API routes for all applications..."
# kubectl apply -f deploy/gateway-api/cert-manager-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/kube-prometheus-stack-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/loki-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/argo-rollouts-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/keda-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/kargo-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -
# kubectl apply -f deploy/gateway-api/openunison-httproute.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "=== Setup Complete ==="
echo ""
echo "Run command: sudo minikube tunnel -p demo"
echo ""
echo "Open http://argocd.localhost in browser"
echo ""
echo "Access URLs after minikube tunnel is running:"
echo "  - ArgoCD: http://argocd.localhost"
echo "  - Envoy Gateway: http://envoy-gateway.localhost"
echo "  - cert-manager: http://cert-manager.localhost"
echo "  - Prometheus: http://prometheus.localhost"
echo "  - Grafana: http://grafana.localhost"
echo "  - Loki: http://loki.localhost"
echo "  - Argo Rollouts: http://rollouts.localhost"
echo "  - KEDA: http://keda.localhost"
echo "  - Kargo: http://kargo.localhost"
echo "  - OpenUnison: http://openunison.localhost"
