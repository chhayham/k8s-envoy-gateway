# k8s-envoy-gateway

GitOps Demo with ArgoCD and Envoy Gateway

This project demonstrates how to deploy multiple Kubernetes applications using **ArgoCD** for GitOps, with all services exposed through **Envoy Gateway** using the Gateway API. The demo includes:

- Gateway API CRDs (installed via kubectl or setup script)
- ArgoCD install (bootstrap)
- Envoy Gateway deployed via an ArgoCD `Application` manifest using OCI registry
- Multiple applications deployed via ArgoCD with automated sync and self-healing
- All services exposed via HTTPRoutes through Envoy Gateway

## Applications Deployed

| Application | Description | Namespace | Access URL |
|-------------|-------------|-----------|------------|
| **cert-manager** | TLS certificate management | cert-manager | cert-manager.localhost |
| **kube-prometheus-stack** | Prometheus & Grafana monitoring stack | monitoring | prometheus.localhost, grafana.localhost |
| **loki** | Log aggregation system | logging | loki.localhost |
| **fluent-bit** | Log processor and forwarder | logging | - |
| **openunison** | Kubernetes authentication portal | openunison | openunison.localhost |
| **kargo** | Kubernetes GitOps workflow automation | kargo | kargo.localhost |
| **argo-rollouts** | Advanced deployment strategies | argo-rollouts | rollouts.localhost |
| **keda** | Kubernetes Event-driven Autoscaling | keda | keda.localhost |
| **envoy-gateway** | Cloud-native API gateway | envoy | envoy-gateway.localhost |

## Requirements

- **Podman** (container runtime for minikube, enable docker compatibility in preferences) 
- **minikube** — single-node Kubernetes cluster (3 nodes with `--nodes=3` flag)
- **kubectl** — Kubernetes CLI
- **Helm** — for ArgoCD installation

## Quick Start

### Using the Setup Script

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script:
- Validates required tools (minikube, kubectl, helm)
- Creates a minikube cluster with 3 nodes (podman driver)
- Installs Gateway API CRDs
- Deploys ArgoCD with OCI repository support
- Deploys Envoy Gateway via kubectl (avoids OCI auth issues)
- Creates Gateway API resources
- Deploys all application manifests via ArgoCD

### Manual Installation

1. **Install Gateway API CRDs**
   ```bash
   kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml?raw=true
   ```

2. **Deploy ArgoCD**
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm upgrade --install argocd argo/argo-cd \
     --version 10.9.2 \
     --namespace argocd \
     --create-namespace \
     -f deploy/argocd/values.yaml \
     --wait
   ```

3. **Deploy ArgoCD Applications**
   ```bash
   # Deploy all applications using the combined manifest
   kubectl apply -f deploy/argocd-applications/all-apps.yaml
   
   # Or deploy individual applications
   kubectl apply -f deploy/argocd-applications/cert-manager-app.yaml
   kubectl apply -f deploy/argocd-applications/kube-prometheus-stack-app.yaml
   kubectl apply -f deploy/argocd-applications/loki-app.yaml
   kubectl apply -f deploy/argocd-applications/fluent-bit-app.yaml
   kubectl apply -f deploy/argocd-applications/openunison-app.yaml
   kubectl apply -f deploy/argocd-applications/kargo-app.yaml
   kubectl apply -f deploy/argocd-applications/argo-rollouts-app.yaml
   kubectl apply -f deploy/argocd-applications/keda-app.yaml
   ```

4. **Deploy Gateway API Resources**
   ```bash
   # Deploy all HTTPRoutes using the combined manifest
   kubectl apply -f deploy/gateway-api/all-routes.yaml
   
   # Or deploy individual HTTPRoutes
   kubectl apply -f deploy/gateway-api/envoy-gateway-routes.yaml
   kubectl apply -f deploy/gateway-api/cert-manager-httproute.yaml
   kubectl apply -f deploy/gateway-api/kube-prometheus-stack-httproute.yaml
   kubectl apply -f deploy/gateway-api/loki-httproute.yaml
   kubectl apply -f deploy/gateway-api/argo-rollouts-httproute.yaml
   kubectl apply -f deploy/gateway-api/keda-httproute.yaml
   kubectl apply -f deploy/gateway-api/openunison-httproute.yaml
   kubectl apply -f deploy/gateway-api/kargo-httproute.yaml
   ```

## Verification

```bash
# ArgoCD apps status
kubectl -n argocd get applications -o wide

# Gateway and HTTPRoute status
kubectl get gateway,httproute -A -o wide

# Check all namespaces
kubectl get all -A
```

### Accessing Services

**1. Start minikube tunnel (in a separate terminal):**
```bash
sudo minikube tunnel -p demo
```

Then access services:
- **ArgoCD Dashboard:** `http://argocd.localhost`
- **Envoy Gateway:** `http://envoy-gateway.localhost`
- **cert-manager:** `http://cert-manager.localhost`
- **Prometheus:** `http://prometheus.localhost`
- **Grafana:** `http://grafana.localhost`
- **Loki:** `http://loki.localhost`
- **OpenUnison:** `http://openunison.localhost`
- **Kargo:** `http://kargo.localhost`
- **Argo Rollouts:** `http://rollouts.localhost`
- **KEDA:** `http://keda.localhost`

## Directory Structure

```
├── deploy/
│   ├── argocd/                   # ArgoCD configuration
│   │   └── values.yaml           # Custom ArgoCD values
│   ├── argocd-applications/      # ArgoCD Application manifests
│   │   ├── all-apps.yaml         # All ArgoCD applications combined
│   │   ├── envoy-gateway-crds-app.yaml   # Envoy Gateway CRDs from OCI registry
│   │   ├── envoy-gateway-app.yaml        # Envoy Gateway from OCI registry
│   │   ├── cert-manager-app.yaml         # cert-manager application
│   │   ├── kube-prometheus-stack-app.yaml # Prometheus & Grafana
│   │   ├── loki-app.yaml                 # Loki log aggregation
│   │   ├── fluent-bit-app.yaml           # Fluent-bit log processor
│   │   ├── openunison-app.yaml           # OpenUnison authentication portal
│   │   ├── kargo-app.yaml                # Kargo workflow automation
│   │   ├── argo-rollouts-app.yaml        # Argo Rollouts
│   │   └── keda-app.yaml                 # KEDA autoscaling
│   └── gateway-api/              # Gateway API resources (HTTPRoutes)
│       ├── all-routes.yaml       # All HTTPRoutes combined
│       ├── envoy-gateway-routes.yaml     # Envoy Gateway routes
│       ├── cert-manager-httproute.yaml
│       ├── kube-prometheus-stack-httproute.yaml
│       ├── loki-httproute.yaml
│       ├── argo-rollouts-httproute.yaml
│       ├── keda-httproute.yaml
│       ├── openunison-httproute.yaml
│       └── kargo-httproute.yaml
└── scripts/
    └── setup.sh                  # idempotent setup script
```

## Configuration

| Component | Version | File |
|-----------|---------|------|
| Gateway API | v1 | `deploy/gateway-api/*.yaml` |
| ArgoCD | 10.9.2 | `deploy/argocd/values.yaml` |
| Envoy Gateway | v1.9.1 | kubectl deployment (OCI: `oci://docker.io/envoyproxy`) |
| cert-manager | v1.17.0 | `deploy/argocd-applications/cert-manager-app.yaml` |
| kube-prometheus-stack | 69.2.1 | `deploy/argocd-applications/kube-prometheus-stack-app.yaml` |
| loki | 18.13.5 | `deploy/argocd-applications/loki-app.yaml` |
| fluent-bit | 0.58.2 | `deploy/argocd-applications/fluent-bit-app.yaml` |
| openunison | latest | `deploy/argocd-applications/openunison-app.yaml` |
| kargo | main | `deploy/argocd-applications/kargo-app.yaml` |
| argo-rollouts | 2.43.2 | `deploy/argocd-applications/argo-rollouts-app.yaml` |
| keda | 2.21.0 | `deploy/argocd-applications/keda-app.yaml` |

### Key Configuration Notes

- **Gateway API version:** `v1` (`Gateway`, `HTTPRoute`)
- **ArgoCD v3.x:** The Application API schema has changed - the Helm chart configuration fields (`chart`, `repoURL`, `targetRevision`) are at the same level as `helm`, not nested inside it
- **ArgoCD uses OCI registries** (`oci://docker.io/envoyproxy`) to pull Envoy Gateway Helm charts at sync time
- The Envoy Gateway listener allows routes from all namespaces (`allowedRoutes.namespaces.from: All`)
- All applications have `automated: true` with `prune: true` and `selfHeal: true`
- Resource limits and requests are set for all applications

### Accessing Services

**ArgoCD Dashboard:**
1. Run `sudo minikube tunnel -p demo` in a separate terminal
2. Open `http://argocd.localhost` in your browser
3. Username: `admin`
4. Password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

**Envoy Gateway:**
- HTTP traffic: `http://envoy-gateway.localhost`
- Envoy Gateway metrics: `http://envoy-gateway.localhost/metrics`

## Troubleshooting

### ArgoCD app not syncing
```bash
kubectl -n argocd get applications -o wide
kubectl -n argocd logs deploy/argocd-application-controller
```

### Gateway not accepting routes
```bash
kubectl get gateway -A -o wide
kubectl get httproute -A -o wide
kubectl -n envoy get pods,svc
```

### Check route status
```bash
# Check if routes are accepted and resolved
kubectl get httproute -A -o wide
kubectl get httproute <name> -n <namespace> -o yaml
```

### ArgoCD UI not loading
- Verify the `HTTPRoute` conditions: `kubectl -n argocd get httproute argocd-server -o yaml`
- Check the `HTTPRoute.status.parents[].conditions` for `Accepted` / `ResolvedRefs`
- Confirm the `HTTPRoute` `parentRefs` match the Envoy Gateway `name` and `namespace`

## Development

```bash
# Using Makefile
make setup

# Or run the setup script directly
chmod +x scripts/setup.sh
./scripts/setup.sh

# Clean up
make clean
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT — see [LICENSE](LICENSE) for details.
