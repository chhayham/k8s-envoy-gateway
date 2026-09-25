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

minikube start --profile=demo --driver=podman --nodes=3

# Manually install Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml?raw=true

helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install argocd argo/argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_cd_chart_version \
  --namespace argocd \
  --create-namespace \
  -f deploy/argocd/values.yaml \
  --wait

# Ensure namespace exists (redundant but safe)
kubectl create namespace envoy --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f deploy/argocd-applications/envoy-gateway-crds-app.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f deploy/argocd-applications/envoy-gateway-app.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f deploy/envoy/envoy-gateway.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "run command: minikube tunnel -p demo"

echo "open http://argocd.localhost in browser"