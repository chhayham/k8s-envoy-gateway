# Project Summary - k8s-envoy-gateway GitOps Demo

## Overview
This project demonstrates deploying **Envoy Gateway** to a kind cluster using **ArgoCD** for GitOps. The implementation follows a GitOps-first approach with all resources managed via ArgoCD `Application` manifests.

## Project Structure
```
.
├── kind/
│   └── kind-config.yaml          # Multi-node kind cluster config (1 control-plane, 2 workers)
├── deploy/
│   ├── gateway-api-crd/
│   │   └── gateway-api-crds.yaml # Gateway API v1.0.0 CRDs (bootstrap)
│   ├── argocd/
│   │   ├── values.yaml           # ArgoCD base helm values (v2.11.0)
│   │   └── httproute-values.yaml # ArgoCD server.httproute config (v2.11.0)
│   └── apps/
│       └── env-gateway-app.yaml  # Envoy Gateway ArgoCD Application (v1.2.0)
├── docs/
│   └── architecture.md           # Architecture and walkthrough docs
├── scripts/
│   └── setup.sh                  # Idempotent bootstrap script
├── README.md                     # Main documentation
├── QUICKSTART.md                 # Quick start guide
└── PROJECT_SUMMARY.md            # This file
```

## Key Components

### 1. Gateway API CRDs
- Location: `deploy/gateway-api-crd/gateway-api-crds.yaml`
- Version: v1.0.0 (stable)
- Resources: Gateway, HTTPRoute, TCPRoute, TLSRoute, UDPRoute, GatewayClass

### 2. ArgoCD Configuration
- **Base values** (`deploy/argocd/values.yaml`):
  - ArgoCD v2.11.0
  - Disabled: Dex, notifications, metrics, grafana, prometheus
  - RBAC set to `role:readonly` (demo-only)

- **HTTPRoute values** (`deploy/argocd/httproute-values.yaml`):
  - Experimental `server.httproute` feature enabled
  - Hostname: `argocd.example.local`
  - ParentRef: `envoy-gateway` in `envoy-gateway` namespace
  - Path prefix: `/`

### 3. Envoy Gateway ArgoCD Application
- Location: `deploy/apps/env-gateway-app.yaml`
- Chart: `gateway` from `https://envoyproxy.github.io/gateway-helm`
- Version: v1.2.0
- Namespace: `envoy-gateway`
- SyncPolicy: automated with prune and selfHeal enabled

## GitOps Flow

1. **Bootstrap** (direct kubectl/helm):
   - Install Gateway API CRDs
   - Deploy ArgoCD with base values

2. **GitOps** (ArgoCD sync):
   - ArgoCD reads `env-gateway-app.yaml` and deploys Envoy Gateway from Helm chart
   - ArgoCD's `server.httproute` creates an HTTPRoute referencing Envoy Gateway

3. **Traffic routing**:
   - External requests → Envoy Gateway → HTTPRoute → ArgoCD Service
   - Hostname: `argocd.example.local`

## Configuration Values

| Component | Version | File |
|-----------|---------|------|
| Gateway API | v1.0.0 | `deploy/gateway-api-crd/gateway-api-crds.yaml` |
| ArgoCD | v2.11.0 | `deploy/argocd/values.yaml`, `deploy/argocd/httproute-values.yaml` |
| Envoy Gateway | v1.2.0 | `deploy/apps/env-gateway-app.yaml` |

## Routes

| Hostname | Service | Path | Status |
|----------|---------|------|--------|
| `argocd.example.local` | `argocd-server` | `/` | Via Envoy Gateway HTTPRoute |

## Verification Commands

```bash
# Check ArgoCD apps
kubectl -n argocd get applications -o wide

# Check Gateway and HTTPRoute
kubectl get gateway,httproute -A -o wide

# Test ArgoCD UI
curl http://argocd.example.local/

# Check ArgoCD server logs
kubectl -n argocd logs deploy/argocd-server

# Check Envoy Gateway pods
kubectl -n envoy-gateway get pods,svc,httproute
```

## Notes

- The `server.httproute` feature in ArgoCD is marked **EXPERIMENTAL** - pinned chart versions are required for stability
- The Envoy Gateway listener must allow routes from the `argocd` namespace
- The kind cluster uses podman as the container runtime (config: `kind-config.yaml`)
- The setup script (`scripts/setup.sh`) is idempotent and validates prerequisites

## Changelog

- **v0.1.0** (initial)
  - Project structure created
  - Gateway API CRDs (v1.0.0) configured
  - ArgoCD (v2.11.0) installed with base values
  - Envoy Gateway (v1.2.0) deployed via ArgoCD Application
  - ArgoCD dashboard exposed via `server.httproute` (experimental)
  - Documentation updated (README, architecture.md)
