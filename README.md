# Kubernetes Envoy Gateway Demo

This project bootstraps a Kubernetes cluster with Envoy Gateway and ArgoCD for GitOps-based application management.

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/) - Local Kubernetes development
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [helm](https://helm.sh/docs/intro/install/) - Kubernetes package manager
- [podman](https://podman.io/getting-started/installation) - Container runtime for minikube
- [make](https://www.gnu.org/software/make/) - Build automation tool

## Quick Start

### Using the Setup Script

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### Using Makefile

```bash
make setup
```

The setup script:
- Validates required tools (podman, kubectl, minikube, helm)
- Creates a minikube cluster with 3 nodes (podman driver)
- Installs KEDA CRDs
- Deploys ArgoCD via Helm
- Deploys ApplicationSet from manifests
- Waits for ArgoCD components to be ready

### Manual Installation

1. **Deploy ArgoCD**
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm upgrade --install argocd argo/argo-cd \
     --version 10.9.2 \
     --namespace argocd \
     --create-namespace \
     -f deploy/argocd/values.yaml \
     --wait
   ```

2. **Deploy ArgoCD ApplicationSet**
   ```bash
   kubectl apply -f deploy/argocd-applicationsets/root.yaml
   ```

## Deployed Applications

| Application | Version | Manifest | Notes |
|-------------|---------|----------|-------|
| Gateway API | v1 | `deploy/httproute/*.yaml` | Gateway API CRDs and routes |
| ArgoCD | 10.9.2 | `deploy/argocd/values.yaml` | GitOps CD |
| Envoy Gateway | v1.9.1 | `oci://docker.io/envoyproxy` | Gateway API implementation |
| cert-manager | v1.21.2 | `deploy/argocd-applications/cert-manager/config.yaml` | Certificate management |
| argo-rollouts | 2.43.2 | `deploy/argocd-applications/argo-rollouts/config.yaml` | Progressive delivery |
| keda | 2.21.0 | `deploy/argocd-applications/keda/config.yaml` | Kubernetes event-driven autoscaling |
| kube-prometheus-stack | 91.7.0 | `deploy/argocd-applications/kube-prometheus-stack/config.yaml` | Prometheus monitoring |
| loki | 18.13.6 | `deploy/argocd-applications/loki/config.yaml` | Log aggregation |
| fluent-bit | 0.58.2 | `deploy/argocd-applications/fluent-bit/config.yaml` | Log collection |
| openunison | 3.0.31 | `deploy/argocd-applications/openunison/config.yaml` | Identity management |
| kargo | 1.11.2 | `deploy/argocd-applications/kargo/config.yaml` | GitOps workflow |

## Application Management

### ArgoCD Application Pattern

Applications use the ArgoCD Application API with the following configuration:
- **Source**: OCI Helm charts from various repositories
- **Sync Policy**: Automated sync with prune and self-healing enabled
- **Namespace**: Each app deployed to its own namespace with `createNamespace=true`

### Adding New Applications

1. Create a directory under `deploy/argocd-applications/<app-name>/`
2. Add `config.yaml` with the following structure:

```yaml
addon:
  - name: <app-name>
    chart: <chart-name>
    repoURL: <helm-repo-url>
    targetRevision: <version>
    namespace: <namespace>
    helmValues: |
      <yaml-helm-values>
```

3. Optionally add an Application manifest at `deploy/argocd-applications/<app-name>/app-manifest.yaml`
4. Add HTTPRoute at `deploy/httproute/<app-name>-httproute.yaml` if the app needs external access

## Accessing Services

**ArgoCD Dashboard:**
1. Run `sudo minikube tunnel -p demo` in a separate terminal
2. Open `http://argocd.localhost` in your browser
3. Username: `admin`
4. Password: `admin`

**Envoy Gateway:**
- HTTP traffic: `http://envoy-gateway.localhost`
- Envoy Gateway metrics: `http://envoy-gateway.localhost/metrics`

**Application Routes:**
- Argo Rollouts: `http://rollouts.localhost`
- KEDA: `http://keda.localhost`
- cert-manager: `http://cert-manager.localhost`
- Kargo: `http://kargo.localhost`
- Prometheus: `http://prometheus.localhost`
- Loki: `http://loki.localhost`

## Key Configuration Notes

- **Gateway API version:** `v1` (`Gateway`, `HTTPRoute`)
- **ArgoCD v3.x:** Uses OCI registries for Helm charts (`oci://docker.io/envoyproxy`)
- **Envoy Gateway listener:** Allows routes from all namespaces (`allowedRoutes.namespaces.from: All`)
- **All applications:** Have `automated: true` with `prune: true` and `selfHeal: true`
- **Resource limits:** Set for all applications (CPU/memory)

## Troubleshooting

### ArgoCD app not syncing
```bash
kubectl -n argocd get applications -o wide
kubectl -n argocd logs deploy/argocd-application-controller
kubectl -n argocd get applicationsets.argoproj.io cluster-addons -o yaml
```

### Gateway not accepting routes
```bash
kubectl get gateway -A -o wide
kubectl get httproute -A -o wide
kubectl -n envoy-gateway-system get pods,svc
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

## Project Structure

```
├── deploy/
│   ├── argocd/                    # ArgoCD Helm values
│   │   └── values.yaml
│   ├── argocd-applications/       # Application manifests
│   │   ├── <app-name>/
│   │   │   ├── config.yaml        # ApplicationSet config
│   │   └── httproute/             # HTTPRoute manifests
│   │       └── <app>-httproute.yaml
│   ├── argocd-applicationsets/    # ApplicationSet manifests
│   │   └── root.yaml
│   └── httproute/                 # HTTPRoute manifests (alternative location)
│       └── *.yaml
├── scripts/
│   └── setup.sh                   # Bootstrap script
├── Makefile                       # Convenience targets
└── README.md
```

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
