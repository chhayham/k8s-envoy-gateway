# k8s-envoy-gateway - GitOps Demo with ArgoCD and Envoy Gateway

## Overview
This repository demonstrates how to deploy **Envoy Gateway** to a kind cluster using **ArgoCD** for GitOps. The demo includes:

1. **Bootstrap**: Gateway API CRDs and ArgoCD install
2. **GitOps**: ArgoCD Application for Envoy Gateway
3. **Exposure**: ArgoCD dashboard exposed via Envoy Gateway using the chart's built-in `server.httproute`

## Prerequisites
- **Podman** (for kind runtime and image builds)
- **Kind** (multi-node Kubernetes cluster)
- **kubectl** (Kubernetes CLI)

## Quick Start

### 1. Clone the repo
```bash
git clone https://github.com/your-org/k8s-envoy-gateway.git
cd k8s-envoy-gateway
```

### 2. Run the setup script
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This script:
- Creates a kind cluster (if not present)
- Installs Gateway API CRDs
- Deploys ArgoCD
- Verifies everything is running

### 3. Port-forward ArgoCD UI (optional)
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```
Then open `http://localhost:8080` in your browser.

### 4. Verify Envoy Gateway and ArgoCD UI
```bash
# Check ArgoCD apps
kubectl -n argocd get applications -o wide

# Check Gateway and HTTPRoute
kubectl get gateway,httproute -A -o wide

# Test ArgoCD UI via Gateway (after Envoy Gateway is synced)
curl http://argocd.example.local/
```

## Directory Structure
```
.
├── kind/
│   └── kind-config.yaml        # kind cluster definition
├── deploy/
│   ├── gateway-api-crd/        # Gateway API CRDs (bootstrap)
│   ├── argocd/                 # ArgoCD install + httproute values
│   └── apps/                   # ArgoCD Application manifests (GitOps)
├── docs/
│   └── architecture.md         # Architecture walkthrough
└── scripts/
    └── setup.sh                # Idempotent setup script
```

## Routes Overview
| Hostname | Service | Path | Notes |
|----------|---------|------|-------|
| `argocd.example.local` | `argocd-server` | `/` | ArgoCD dashboard via Envoy Gateway |

## Troubleshooting

### ArgoCD app not syncing
```bash
kubectl -n argocd get applications env-gateway -o wide
kubectl -n argocd logs deploy/argocd-application-controller
```

### Gateway not accepting routes
```bash
kubectl get gateway -A -o wide
kubectl get httproute -A -o wide
kubectl -n envoy-gateway logs -l app.kubernetes.io/name=envoy-gateway
```

### ArgoCD UI not loading
- Verify the `HTTPRoute` conditions: `kubectl -n argocd get httproute <name> -o yaml`
- Check the `HTTPRoute.status.parents[].conditions` for `Accepted` / `ResolvedRefs`
- Confirm the `HTTPRoute` `parentRefs` match the Envoy Gateway `name` and `namespace`

## Next Steps
- Add backend services and `HTTPRoute` rules (see `docs/architecture.md`)
- Configure GitHub OAuth for ArgoCD (replace `dex.enabled: false`)
- Add TLS termination for production use
