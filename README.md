# k8s-envoy-gateway
GitOps Demo with ArgoCD and Envoy Gateway

## About
This project demonstrates how to deploy **Envoy Gateway** to a kind cluster using **ArgoCD** for GitOps. The demo includes:

- Gateway API CRDs (bootstrap)
- ArgoCD install (bootstrap)
- Envoy Gateway deployed via an ArgoCD `Application` manifest
- ArgoCD dashboard exposed via Envoy Gateway using the chart's built-in `server.httproute` (no manual `HTTPRoute` needed)

### Requirements
- **Podman** (image builds and kind runtime)
- **Kind** — multi-node Kubernetes cluster
- **kubectl**

**kind configuration example:**
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

### Steps

1. **Install Gateway API CRDs**
   - `kubectl apply -f deploy/gateway-api-crd/`

2. **Deploy ArgoCD to the kind cluster**
   - `helm install argocd argo-cd/argo-cd -n argocd --create-namespace -f deploy/argocd/values.yaml`

3. **Create ArgoCD Application for Envoy Gateway**
   - Commit `deploy/apps/env-gateway-app.yaml` (GitOps) so ArgoCD deploys Envoy Gateway from the specified source path

4. **Expose ArgoCD dashboard via Envoy Gateway**
   - Upgrade ArgoCD with `deploy/argocd/httproute-values.yaml` so the chart creates its own `HTTPRoute` (via `server.httproute`)

   ```bash
   helm upgrade argocd argo-cd/argo-cd -n argocd -f deploy/argocd/httproute-values.yaml
   ```

### Verification

```bash
# ArgoCD apps status
kubectl -n argocd get applications -o wide

# Gateway and HTTPRoute status
kubectl get gateway,httproute -A -o wide

# Test ArgoCD UI via Gateway
curl http://argocd.example.local/
```

### Quick Start Script

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

---

## Directory layout
```
.
├── kind/
│   └── kind-config.yaml        # kind cluster definition (control-plane + 2 workers)
├── deploy/
│   ├── gateway-api-crd/        # Gateway API CRDs (bootstrap step 1)
│   ├── argocd/                 # ArgoCD install (bootstrap step 2)
│   │   ├── values.yaml         # base ArgoCD helm values
│   │   └── httproute-values.yaml  # server.httproute -> ArgoCD's own HTTPRoute (step 4)
│   └── apps/                   # ArgoCD Application manifests (GitOps step 3)
│       └── env-gateway-app.yaml
├── docs/
│   └── architecture.md         # architecture and walkthrough docs
└── scripts/
    └── setup.sh                # idempotent setup script
```

---

## Routes Overview
| Hostname | Service | Path | Notes |
|----------|---------|------|-------|
| `argocd.example.local` | `argocd-server` | `/` | ArgoCD dashboard via Envoy Gateway |

---

## Notes
- Gateway API version: `v1` (`Gateway`, `HTTPRoute`)
- ArgoCD version: `v2.11.0` (pin in `deploy/argocd/values.yaml`)
- Envoy Gateway version: `v1.2.0` (pin in `deploy/apps/env-gateway-app.yaml`)
- ArgoCD's `server.httproute` is marked **EXPERIMENTAL** — pinned chart version required
- The Envoy Gateway listener must allow routes from the `argocd` namespace (`allowedRoutes.namespaces.from: All`)

---

## Changelog
See [CHANGELOG.md](CHANGELOG.md) for version history.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidance.

## License
MIT — see [LICENSE](LICENSE) for details.
