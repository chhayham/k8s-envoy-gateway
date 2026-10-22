# Kubernetes Envoy Gateway Demo

This project bootstraps a Kubernetes cluster with a Terraform-managed platform (Gateway API, cert-manager, Envoy Gateway, Keycloak, ArgoCD) and uses ArgoCD ApplicationSets for GitOps-based application management.

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/) - Local Kubernetes development
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [terraform](https://developer.hashicorp.com/terraform/install) - Infrastructure as code (cluster bootstrap)
- [podman](https://podman.io/getting-started/installation) - Container runtime for minikube
- [make](https://www.gnu.org/software/make/) - Build automation tool
- helm (optional) - only needed for manual debugging, not for the bootstrap

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
- Validates required tools (podman, kubectl, minikube, terraform)
- Creates a minikube cluster with 2 nodes (podman driver)
- Runs `terraform init`
- Bootstraps in two Terraform phases: first a base plan/apply of the module chain up to Keycloak (`plan/base.tfplan`, `-target=module.keycloak` — no Keycloak access needed yet), then the full plan/apply (`plan/terraform.tfplan`). State is stored locally in `terraform/state/`
- Runs a temporary localhost port-forward to Keycloak during the full plan/apply (the keycloak Terraform provider provisions the SSO realm objects — stopped on exit)
- Applies the ArgoCD ApplicationSets from `deploy/argocd-applicationsets/root.yaml`
- Waits for ArgoCD components to be ready

> **Existing cluster?** If the cluster was bootstrapped by the pre-Terraform version of this repo, recreate it first: `make reset`

### Terraform Workflow (manual)

```bash
make tf-init       # terraform init
make tf-base-plan  # plan the base chain (-> module.keycloak); FRESH clusters only
make tf-base-apply # apply the base plan (brings Keycloak up)
make tf-plan       # terraform plan -out=terraform/plan/terraform.tfplan
make tf-apply      # terraform apply terraform/plan/terraform.tfplan
make tf-destroy    # terraform destroy (asks for confirmation)
```

`terraform plan` always writes to a file (`terraform/plan/terraform.tfplan`) and `terraform apply` always consumes that file, so an inspected plan is exactly what gets applied.

> **Fresh cluster?** The full plan logs into Keycloak through a localhost port-forward, but the Keycloak service only exists after the base modules are applied. On a fresh cluster run `make tf-base-plan && make tf-base-apply` first (or let `scripts/setup.sh` / `make reset` do it) — day-2 `make tf-plan`/`make tf-apply` runs don't need the base phase.

#### Cluster configuration

The `kubernetes` and `helm` providers are pinned via variables in `terraform/variables.tf`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `kubeconfig_path` | `~/.kube/config` | Kubeconfig file. **Required to be set**: the `kubernetes_manifest` resource does not auto-discover `~/.kube/config` or `$KUBECONFIG` |
| `kubeconfig_context` | `demo` | Kubeconfig context (minikube profile) to target |

#### Module dependency chain

```
gateway-api  <  cert-manager  <  envoy-gateway  <  keycloak  <  argocd
```

The KEDA CRDs are installed independently of the chain. The pod CNI is minikube's own `kindnet` (podman driver) — no second CNI is deployed.

## Deployed Components

### Terraform-managed (`terraform/modules/`)

| Component | Version | Module | Notes |
|-----------|---------|--------|-------|
| Gateway API CRDs | v1.9.1 | `terraform/modules/gateway-api` | Vendored CRDs (+ admission policies) from `gateway-crds-helm`, experimental channel |
| KEDA CRDs | 2.21.0 | `terraform/modules/keda` | Vendored CRDs; the operator stays ArgoCD-managed |
| cert-manager | v1.21.2 | `terraform/modules/cert-manager` | Gateway API injector + bootstrap issuers/CA (local chart) |
| Envoy Gateway | v1.9.1 | `terraform/modules/envoy-gateway` | Controller + GatewayClass + Gateway (local chart) |
| Keycloak | 25.2.0 | `terraform/modules/keycloak` | Bitnami chart (`bitnamilegacy` images), bundled PostgreSQL; SSO realm objects via the keycloak provider (`terraform/keycloak-sso.tf`) |
| ArgoCD | 10.9.2 | `terraform/modules/argocd` | GitOps CD |

### ArgoCD ApplicationSet-managed (`deploy/argocd-applications/`)

| Application | Version | Manifest |
|-------------|---------|----------|
| Argo Rollouts | 2.43.2 | `deploy/argocd-applications/argo-rollouts/config.yaml` |
| KEDA (operator) | 2.21.0 | `deploy/argocd-applications/keda/config.yaml` |
| kube-prometheus-stack | 91.7.0 | `deploy/argocd-applications/kube-prometheus-stack/config.yaml` |
| loki | 18.13.6 | `deploy/argocd-applications/loki/config.yaml` |
| fluent-bit | 0.58.2 | `deploy/argocd-applications/fluent-bit/config.yaml` |
| Kargo | 1.11.2 | `deploy/argocd-applications/kargo/config.yaml` |

## Application Management

### ArgoCD Application Pattern

Applications are generated by the ApplicationSet in `deploy/argocd-applicationsets/root.yaml` from the `deploy/argocd-applications/<app-name>/config.yaml` files:
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

3. Optionally add a resources manifest at `deploy/argocd-applications/<app-name>/resources/<name>.yaml` (synced by the `cluster-addons-resources` ApplicationSet)
4. Add an HTTPRoute at `deploy/httproute/<app-name>/<app-name>-httproute.yaml` if the app needs external access (synced by the `cluster-addons-httproute` ApplicationSet)
5. Commit and push, then update the pinned `revision` in `deploy/argocd-applicationsets/root.yaml` to the new branch/commit

## Accessing Services

Run `sudo minikube tunnel -p demo` in a separate terminal first.

| Route | Service | Credentials |
|-------|---------|-------------|
| `http://argocd.localhost` | ArgoCD dashboard | SSO via Keycloak (GitHub) — or `admin` / `admin` fallback |
| `http://keycloak.localhost` | Keycloak admin console | `admin` / `admin` |
| `http://rollouts.localhost` | Argo Rollouts dashboard | - |
| `http://prometheus.localhost` | Prometheus | - |
| `http://grafana.localhost` | Grafana | `admin` / `admin` |
| `http://alert-manager.localhost` | Alertmanager | - |
| `http://loki.localhost` | Loki | - |
| `http://kargo.localhost` | Kargo | - |

## Key Configuration Notes

- **Gateway API version:** `v1` (`Gateway`, `HTTPRoute`), experimental CRD channel
- **Envoy Gateway:** v1.9.1, listener allows routes from all namespaces (`allowedRoutes.namespaces.from: All`)
- **cert-manager:** Gateway API injector enabled (`config.gatewayAPI.enabled: true`); bootstrap self-signed CA for `*.localhost` provisioned via ClusterIssuers
- **Keycloak:** Bitnami chart with bundled PostgreSQL; exposed through the Envoy Gateway (ClusterIP service + HTTPRoute); serves as ArgoCD's OIDC identity provider (native SSO, dex disabled) — see [ArgoCD SSO (Keycloak)](#argocd-sso-keycloak). Image repositories point at `docker.io/bitnamilegacy` because Bitnami no longer publishes the versioned tags under `docker.io/bitnami`
- **CRD-only charts are vendored, not helm releases:** `gateway-crds-helm` (~4 MB) overflows helm's 1 MiB release-Secret limit, so the exact chart output is vendored under `modules/gateway-api/crds/` and applied with `kubernetes_manifest`. The cert-manager bootstrap issuers/CA and the cluster GatewayClass/Gateway live in the local charts under `terraform/charts/` because `kubernetes_manifest` validates CRD-backed kinds against the live API at plan time (deferral is experimental-only in stable Terraform)
- **CNI:** minikube v1.39 (podman driver) ships `kindnet` as the cluster CNI. Do not deploy a second CNI (e.g. Calico) alongside it — the coexistence corrupts cross-node pod routing
- **All ArgoCD apps:** `automated: true` with `prune: true` and `selfHeal: true`
- **Terraform state:** local backend in `terraform/state/terraform.tfstate` (git-ignored); provider versions locked in `terraform/.terraform.lock.hcl`

## GitHub Social Login (Keycloak)

Keycloak can offer **"Sign in with GitHub"** on its login page via a GitHub
OAuth App. The `master` realm is provisioned by **Terraform**
(`terraform/keycloak-sso.tf`,
[keycloak provider](https://registry.terraform.io/providers/keycloak/keycloak),
Keycloak 26.x): it creates the `github` identity provider (when credentials
are present), the public `argocd` OIDC client (PKCE S256), the `groups`
client scope and the `ArgoCDAdmins` realm group, and gives the configured
GitHub account (default `chhayham`, `var.argocd_admin_username`) the `admin`
realm role — same access as the local `admin` account, admin console
included — plus membership in `ArgoCDAdmins` (see
[ArgoCD SSO (Keycloak)](#argocd-sso-keycloak)). The login theme renders
every enabled identity provider, so no authentication-flow change is needed
(and Keycloak 26 forbids modifying built-in flows).

This repo is public, so **no secret is committed**: the OAuth credentials
live in the git-ignored `terraform/terraform.auto.tfvars`, which Terraform
loads automatically.

**One-time setup — create the GitHub OAuth App:**

1. GitHub → Settings → Developer settings → **OAuth Apps** → *New OAuth App*
2. Fill in:
   - **Application name:** `k8s-envoy-gateway`
   - **Homepage URL:** `http://keycloak.localhost`
   - **Authorization callback URL:** `http://keycloak.localhost/realms/master/broker/github/endpoint`
3. Copy `terraform/terraform.auto.tfvars.example` to
   `terraform/terraform.auto.tfvars` (git-ignored — never commit it) and
   fill in the issued credentials. With both values empty, Terraform plans
   fine but skips creating the `github` identity provider.

**Enable it:**

```bash
make tf-plan   # shows: keycloak_oidc_github_identity_provider.github will be created
make tf-apply
# then check http://keycloak.localhost — the login page shows "Or sign in with → GitHub".
```

**Update the credentials later:** edit `terraform/terraform.auto.tfvars`
and re-run `make tf-plan && make tf-apply` — the provider updates the
identity provider in place.

> Migrated from the old Job-based setup? The git-ignored
> `secrets/keycloak-github.yaml` is no longer used — copy its values into
> `terraform/terraform.auto.tfvars` and delete the file.

## ArgoCD SSO (Keycloak)

ArgoCD login goes through Keycloak with **native OIDC** (dex is disabled) using
the authorization-code flow with **PKCE S256** — no client secret involved.

**Flow:** ArgoCD UI/CLI → Keycloak (`http://keycloak.localhost`) → sign in with
GitHub (or a local Keycloak account) → redirect back to
`http://argocd.localhost/auth/callback`.

**How the pieces fit together:**

| Piece | Location |
|-------|----------|
| OIDC provider config (`issuer`, `clientID`, PKCE, requested scopes) | `terraform/modules/argocd/values.yaml` → `configs.cm.oidc.config` (rendered into `argocd-cm`) |
| Server URL (`http://argocd.localhost` — base of the OIDC redirect URI) | `terraform/modules/argocd/values.yaml` → `configs.cm.url` |
| Role mapping: `ArgoCDAdmins` group → ArgoCD `role:admin` (via the `groups` token claim) | `terraform/modules/argocd/values.yaml` → `configs.rbac.policy.csv` (rendered into `argocd-rbac-cm`, `scopes: [groups]`) |
| In-cluster name resolution for the issuer (`keycloak.localhost` → Keycloak service ClusterIP, injected as pod `hostAliases`) | `terraform/modules/argocd/main.tf` |
| Keycloak side: public `argocd` client (PKCE S256, UI + CLI redirect URIs), `groups` client scope (Group Membership mapper), `argocd-username` client scope (Hardcoded Claim mapper: `email` = demo username), `ArgoCDAdmins` realm group, `github` identity provider, GitHub-user membership | Terraform, `terraform/keycloak-sso.tf` (keycloak provider) |
| First IdP login: the GitHub IdP uses a custom passwordless flow (`sso first broker login`: create-or-auto-link) instead of the built-in `first broker login` flow, which requires a local password the demo user does not have | Terraform, `terraform/keycloak-sso.tf` (`keycloak_authentication_flow` + `keycloak_authentication_execution` + the IdP's `first_broker_login_flow_alias`) |

The issuer URL is the **browser-reachable** name `keycloak.localhost` (served
through the Envoy Gateway + `minikube tunnel`). The argocd-server pod itself
cannot resolve that host name, so the Terraform module merges a `hostAliases`
entry pointing it at the Keycloak service's ClusterIP for the server-to-server
token exchange.

**First-login flow:** Keycloak's built-in `first broker login` flow cannot
complete for the passwordless demo user — `idp-confirm-link` /
`idp-username-password-form` require a local password (the login would always
fail with `invalid_user_credentials`), and with those disabled the flow falls
through to a branch whose condition check crashes on the null session user
(a Keycloak 26 bug). Keycloak also forbids modifying built-in flows via the
admin API, so Terraform defines a minimal **custom** flow —
`sso first broker login`, two ALTERNATIVE steps: `idp-create-user-if-unique`
(creates the user for new identities, records existing ones) then
`idp-auto-link` (links the identity to the existing user and sets the session
user; no password prompts) — and assigns it to the GitHub identity provider
via `first_broker_login_flow_alias`, which Keycloak honors in preference to
the realm default. The first GitHub login therefore just links `github` to
the pre-created user; later logins skip the flow entirely.

**Display username:** ArgoCD 3.x removed `usernameClaim` from `oidc.config`;
for SSO logins the username shown in the UI is hardcoded as the token's
`email` claim (first), then `federated_claims.user_id`, then `sub` (the
Keycloak user UUID). The demo user has no email and no standard Keycloak 26
mapper can synthesize the nested `federated_claims` claim, so the username is
exposed as `email` instead: the `argocd-username` client scope adds a
hardcoded `email` claim (`var.argocd_admin_username`) to the `argocd`
client's tokens. (The keycloak provider v5.x cannot persist `keycloak_user`
`attributes` on update, which rules out the attribute-mapper variant.) RBAC
is unaffected — policy matching still uses the `sub`-based user identifier,
not the display name.

**Log in:**

- UI: open `http://argocd.localhost` → *Log in with Keycloak* → sign in.
- CLI: `argocd login http://argocd.localhost --sso` (opens a browser; the
  `argocd` client already carries the CLI redirect URIs).

**Access model:** membership in the Keycloak realm group `ArgoCDAdmins` maps to
ArgoCD `role:admin`; Terraform adds the configured GitHub user
(`var.argocd_admin_username`, default `chhayham`) to the group.
Other Keycloak users can authenticate but hold no ArgoCD RBAC role
(`policy.default` stays deny). The local `admin` / `admin` account remains
available as a fallback.

**Verify:**

```bash
# SSO provider exposed to the login page
curl -s http://argocd.localhost/api/v1/settings | python3 -m json.tool | grep -A6 oidcConfig
# OIDC flow + callback on the server (a successful login has no `error=` in the callback)
kubectl -n argocd logs deploy/argocd-server | grep -E 'authorization_code flow|Callback' | tail
```

## Troubleshooting

### Terraform

```bash
make tf-plan                          # inspect changes before applying
make tf-apply                         # apply the saved plan
kubectl -n <ns> get pods              # check a component
```

If an apply fails mid-way, fix the cause and re-run `make tf-plan && make tf-apply` — Terraform converges from the local state.

The keycloak provider provisions the SSO objects in the Keycloak `master`
realm (`terraform/keycloak-sso.tf`). It performs its initial login during
plan/apply/destroy and reaches Keycloak through `localhost:18082`
(`scripts/keycloak-port-forward.sh`, started automatically by
`make tf-plan`/`make tf-apply`/`make tf-destroy` and `setup.sh`), so the
Keycloak service must be up — except for the base plan/apply
(`make tf-base-plan`/`make tf-base-apply`), which exists precisely because
Keycloak does not exist yet on a fresh cluster:

```bash
scripts/keycloak-port-forward.sh status   # is the forward running?
kubectl -n keycloak get pods,svc          # is Keycloak up?
```

### ArgoCD app not syncing
```bash
kubectl -n argocd get applications -o wide
kubectl -n argocd logs deploy/argocd-application-controller
kubectl -n argocd get applicationsets.argoproj.io cluster-addons -o yaml
```

> The ApplicationSet git `revision` is pinned to a branch (e.g. `2026-10-02-83df44`). After pushing changes, point all three generators at the new pinned branch/commit.

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
- Verify the `HTTPRoute` conditions: `kubectl -n argocd get httproute argocd -o yaml`
- Check the `HTTPRoute.status.parents[].conditions` for `Accepted` / `ResolvedRefs`
- Confirm the `HTTPRoute` `parentRefs` match the Envoy Gateway `name` and `namespace`

## Project Structure

```
├── terraform/                     # Terraform bootstrap (local state)
│   ├── versions.tf                # required_version/provides + local backend
│   ├── providers.tf               # kubernetes + helm (pinned to var.kubeconfig_path/context)
│   ├── variables.tf               # cluster + Keycloak variables
│   ├── main.tf                    # module wiring + dependency chain
│   ├── keycloak-sso.tf            # Keycloak SSO realm objects (keycloak provider, realm 'master')
 │   ├── terraform.auto.tfvars.example # template for local-only vars (GitHub OAuth credentials)
 │   ├── outputs.tf
│   ├── charts/                    # Minimal local charts (no plan-time CRD validation)
│   │   ├── cert-manager-bootstrap/    # bootstrap ClusterIssuers + root CA
│   │   └── envoy-gateway-config/      # GatewayClass + Gateway
│   ├── state/                     # terraform.tfstate (git-ignored)
│   ├── plan/                      # terraform.tfplan (git-ignored)
│   └── modules/
│       ├── gateway-api/           # Gateway API + Envoy Gateway CRDs (vendored under crds/)
│       ├── keda/                  # KEDA CRDs (vendored under crds/)
│       ├── cert-manager/          # cert-manager + bootstrap chart
│       ├── envoy-gateway/         # controller + gateway-config chart
│       ├── keycloak/              # Keycloak + bundled PostgreSQL
│       └── argocd/                # ArgoCD (+ values.yaml)
├── deploy/
│   ├── argocd-applications/       # ApplicationSet sources
│   │   └── <app-name>/
│   │       ├── config.yaml        # ApplicationSet config (required)
│   │       └── resources/         # Optional extra manifests
│   ├── argocd-applicationsets/
│   │   └── root.yaml              # cluster-addons (+httproute +resources) ApplicationSets
│   └── httproute/                 # HTTPRoute manifests for external access
│       └── <app-name>/
│           └── <app-name>-httproute.yaml
├── scripts/
│   ├── setup.sh                   # Bootstrap script (minikube + terraform + ApplicationSets)
│   └── keycloak-port-forward.sh   # Retry-loop port-forward for the keycloak Terraform provider
├── Makefile                       # Convenience targets (setup, tf-*, clean, reset)
└── README.md
```

## Development

```bash
# Using Makefile
make setup

# Or run the setup script directly
chmod +x scripts/setup.sh
./scripts/setup.sh

# Terraform only
make tf-plan && make tf-apply

# Clean up
make clean       # delete the minikube cluster
make reset       # delete + full re-bootstrap
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT — see [LICENSE](LICENSE) for details.
