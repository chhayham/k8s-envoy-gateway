# k8s-envoy-gateway

GitOps Demo with ArgoCD and Envoy Gateway

This project demonstrates how to deploy **Envoy Gateway** to a Kubernetes cluster using **ArgoCD** for GitOps. The demo includes:

- Gateway API CRDs (installed via kubectl or setup script)
- ArgoCD install (bootstrap)
- Envoy Gateway deployed via an ArgoCD `Application` manifest using OCI registry
- ArgoCD dashboard exposed via Envoy Gateway using the chart's built-in `server.httproute` (no manual `HTTPRoute` needed)

## Requirements

- **Podman** (container runtime for minikube)
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
- Deploys Envoy Gateway via GitOps
- Creates Gateway API resources

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

3. **Deploy Envoy Gateway via GitOps**
   ```bash
   kubectl apply -f deploy/arogcd-applications/envoy-gateway-crds-app.yaml
   kubectl apply -f deploy/arogcd-applications/envoy-gateway-app.yaml
   kubectl apply -f deploy/envoy/envoy-gateway.yaml
   ```

## Verification

```bash
# ArgoCD apps status
kubectl -n argocd get applications -o wide

# Gateway and HTTPRoute status
kubectl get gateway,httproute -A -o wide
```

### Accessing Services

**1. Start minikube tunnel (in a separate terminal):**
```bash
sudo minikube tunnel -p demo
```

**2. Open ArgoCD UI in your browser:**
```
http://argocd.localhost
```
- Username: `admin`
- Password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

**3. Open Envoy Gateway in your browser:**
```
http://argocd.localhost
```
- Envoy Gateway metrics: `http://argocd.localhost/metrics` (after configuring Prometheus scrape)

## Directory Layout

```
.
├── deploy/
│   ├── argocd/                   # ArgoCD install (bootstrap step 2)
│   │   └── values.yaml           # base ArgoCD helm values with OCI config
│   ├── arogcd-applications/      # ArgoCD Application manifests (GitOps step 3)
│   │   ├── envoy-gateway-crds-app.yaml  # Envoy Gateway CRDs from OCI registry
│   │   └── envoy-gateway-app.yaml       # Envoy Gateway from OCI registry
│   └── envoy/                    # Gateway API resources
│       └── envoy-gateway.yaml
└── scripts/
    └── setup.sh                  # idempotent setup script
```

## Configuration

| Component | Version | File |
|-----------|---------|------|
| Gateway API | v1 | `deploy/envoy/envoy-gateway.yaml` |
| ArgoCD | 10.9.2 | `deploy/argocd/values.yaml` |
| Envoy Gateway | v1.9.1 | ArgoCD Application manifests (OCI: `oci://docker.io/envoyproxy`) |

### Key Configuration Notes

- **Gateway API version:** `v1` (`Gateway`, `HTTPRoute`)
- **ArgoCD's `server.httproute`** is marked **EXPERIMENTAL** — pinned chart version required
- **ArgoCD uses OCI registries** (`oci://docker.io/envoyproxy`) to pull Envoy Gateway Helm charts at sync time
- The Envoy Gateway listener must allow routes from the `argocd` namespace (`allowedRoutes.namespaces.from: All`)

### Accessing Services

**ArgoCD Dashboard:**
1. Run `sudo minikube tunnel -p demo` in a separate terminal
2. Open `http://argocd.localhost` in your browser
3. Username: `admin`
4. Password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

**Envoy Gateway:**
- HTTP traffic: `http://argocd.localhost`
- Envoy Gateway metrics: `http://argocd.localhost/metrics`

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
