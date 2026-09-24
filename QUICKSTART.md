# GitOps Demo with ArgoCD and Envoy Gateway

This project demonstrates how to deploy **Envoy Gateway** to a kind cluster using **ArgoCD** for GitOps. The demo includes:

- Gateway API CRDs (bootstrap)
- ArgoCD install (bootstrap)
- Envoy Gateway deployed via an ArgoCD `Application` manifest
- ArgoCD dashboard exposed via Envoy Gateway using the chart's built-in `server.httproute` (no manual `HTTPRoute` needed)

## Requirements
- **Podman** (image builds and kind runtime)
- **Kind** — multi-node Kubernetes cluster
- **kubectl**

## Configuration
- Gateway API version: `v1.0.0` (stable)
- ArgoCD version: `v2.11.0`
- Envoy Gateway version: `v1.2.0`

## Steps

1. **Install Gateway API CRDs**
   - `kubectl apply -f deploy/gateway-api-crd/`

2. **Deploy ArgoCD to the kind cluster**
   - `helm install argocd argo-cd/argo-cd -n argocd --create-namespace -f deploy/argocd/values.yaml`

3. **Create ArgoCD Application for Envoy Gateway**
   - Commit `deploy/apps/env-gateway-app.yaml` (GitOps) so ArgoCD deploys Envoy Gateway from the Helm chart

4. **Expose ArgoCD dashboard via Envoy Gateway**
   - Upgrade ArgoCD with `deploy/argocd/httproute-values.yaml` so the chart creates its own `HTTPRoute`

   ```bash
   helm upgrade argocd argo-cd/argo-cd -n argocd -f deploy/argocd/httproute-values.yaml
   ```

## Verification

```bash
# ArgoCD apps status
kubectl -n argocd get applications -o wide

# Gateway and HTTPRoute status
kubectl get gateway,httproute -A -o wide

# Test ArgoCD UI via Gateway
curl http://argocd.example.local/
```

## Routes Overview
| Hostname | Service | Path | Notes |
|----------|---------|------|-------|
| `argocd.example.local` | `argocd-server` | `/` | ArgoCD dashboard via Envoy Gateway |

## Notes
- ArgoCD's `server.httproute` is marked **EXPERIMENTAL** — pinned chart version required
- The Envoy Gateway listener must allow routes from the `argocd` namespace (`allowedRoutes.namespaces.from: All`)
