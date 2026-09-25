#!/bin/bash
set -euo pipefail

argo_cd_chart_version=9.4.3

minikube start --profile=demo --driver=podman --nodes=3

# Manually install Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml

helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version $argo_cd_chart_version \
  --namespace argocd \
  --create-namespace \
  -f deploy/argocd/values.yaml \
  --wait

# Ensure namespace exists
kubectl create namespace envoy --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f deploy/apps/envoy-gateway-crds-app.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f deploy/apps/envoy-gateway-app.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f deploy/apps/envoy-gateway.yaml --dry-run=client -o yaml | kubectl apply -f -

echo "run command: minikube tunnel -p demo"

echo "open http://argocd.localhost in browser"