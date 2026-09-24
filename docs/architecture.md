# k8s-envoy-gateway Architecture Walkthrough

## Overview
This demo shows how to deploy **Envoy Gateway** to a kind cluster using **ArgoCD** for GitOps.

## Architecture Flow
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                  kind Cluster                               │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────────────┐ │
│  │   Gateway API   │  │   ArgoCD         │  │   Envoy Gateway             │ │
│  │   CRDs          │  │   (GitOps)       │  │   (via ArgoCD App)          │ │
│  └─────────────────┘  └──────────────────┘  └─────────────────────────────┘ │
│                              │                                              │
│                              ▼                                              │
│                    ┌─────────────────────┐                                  │
│                    │   Envoy Gateway     │                                  │
│                    │   (Data Plane)      │                                  │
│                    └─────────────────────┘                                  │
│                              │                                              │
│                              ▼                                              │
│                    ┌─────────────────────┐                                  │
│                    │   HTTPRoute         │                                  │
│                    │   (ArgoCD UI)       │                                  │
│                    └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────┘

```

## Steps Breakdown

### 1. Install Gateway API CRDs
- `kubectl apply -f deploy/gateway-api-crd/gateway-api-crds.yaml`
- This creates `Gateway`, `HTTPRoute`, and `GatewayClass` CRDs.

### 2. Deploy ArgoCD
- `helm install argocd argo-cd/argo-cd -n argocd --create-namespace -f deploy/argocd/values.yaml`
- ArgoCD is installed in the `argocd` namespace.
- Base values disable unnecessary components (Dex, notifications, metrics, etc.).

### 3. Deploy Envoy Gateway via GitOps
- Commit `deploy/apps/env-gateway-app.yaml` to the repo.
- ArgoCD reads this `Application` manifest and syncs Envoy Gateway from the official Helm chart.
- The chart version `v1.2.0` is pinned in the Application manifest.

### 4. Expose ArgoCD Dashboard via Envoy Gateway
- Upgrade ArgoCD with `deploy/argocd/httproute-values.yaml`:
  ```bash
  helm upgrade argocd argo-cd/argo-cd -n argocd -f deploy/argocd/httproute-values.yaml
  ```
- The chart creates an `HTTPRoute` that points at the ArgoCD `Service`.
- The `HTTPRoute` references the Envoy Gateway (via `parentRefs`) and is accepted once the Gateway is ready.

## GitOps Flow

1. **Repo Structure**
   ```
   deploy/
   ├── gateway-api-crd/    # Bootstrap CRDs (kubectl apply)
   ├── argocd/             # ArgoCD install + httproute values
   └── apps/               # ArgoCD Application manifests (GitOps)
   ```

2. **ArgoCD Application**
   - `env-gateway-app.yaml` points at a source path (e.g., Envoy Gateway manifests).
   - ArgoCD automatically creates/updates resources in the `envoy-gateway` namespace.

3. **ArgoCD UI Exposure**
   - The `httproute-values.yaml` enables ArgoCD's built-in `server.httproute`.
   - No manual `HTTPRoute` needed — the chart renders it.

## Verification Commands

```bash
# Check ArgoCD apps status
kubectl -n argocd get applications -o wide

# Check Gateway and HTTPRoute
kubectl get gateway,httproute -A -o wide

# Test ArgoCD UI via Gateway
curl http://argocd.example.local/
```

## Notes

- **Gateway API version:** `v1` (`Gateway`, `HTTPRoute`)
- **ArgoCD version:** `v2.11.0` (pin in `deploy/argocd/values.yaml`)
- **Envoy Gateway version:** `v1.2.0` (pin in `deploy/apps/env-gateway-app.yaml`)
- ArgoCD's `server.httproute` is marked **EXPERIMENTAL** — pinned chart version required.
