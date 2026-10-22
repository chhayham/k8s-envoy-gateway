#!/bin/bash
# Idempotent bootstrap: minikube cluster + Terraform-managed platform + ArgoCD.
#
# Terraform workflow (two-phase on fresh clusters — the keycloak provider
# performs its initial login during the FULL plan, which only works once
# Keycloak itself has been applied):
#   1. terraform init
#   2. base plan/apply of the module chain up to Keycloak
#      (plan/base.tfplan, -target=module.keycloak; no Keycloak access needed)
#   3. full plan  -> saved to terraform/plan/terraform.tfplan
#   4. full apply -> applies the saved plan file
#
# Terraform state is stored locally in terraform/state/terraform.tfstate.
# Module dependency chain: gateway-api < cert-manager < envoy-gateway
#                          < keycloak < argocd (calico + keda CRDs are
#                          independent of the chain).

set -euo pipefail  # Fail fast on errors

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
TF_STATE_DIR="${TF_DIR}/state"
TF_PLAN_DIR="${TF_DIR}/plan"
TF_PLAN_FILE="${TF_PLAN_DIR}/terraform.tfplan"
MINIKUBE_PROFILE="demo"
ARGO_NS="argocd"

log() { echo ""; echo "=== $* ==="; }
die() { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*"; }

log "Checking prerequisites"

# Fail fast if any required tool is missing
for tool in podman kubectl minikube terraform; do
    if ! command -v "$tool" &> /dev/null; then
        die "$tool is not installed or not in PATH"
    fi
done

echo "✓ podman found: $(podman --version)"
echo "✓ kubectl found: $(kubectl version --client | grep \"Client\" | awk -F': ' '{print $2}' 2>/dev/null || echo 'version unknown')"
echo "✓ minikube found: $(minikube version | grep version | head -1)"
echo "✓ terraform found: $(terraform version | head -1)"

log "Setting up Minikube Cluster"

# NOTE: no OpenUnison OIDC extra-config anymore — Keycloak is installed
# inside the cluster via Terraform (terraform/modules/keycloak) instead.
MINIKUBE_EXISTS=false
if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
    MINIKUBE_EXISTS=true
fi

if [ "$MINIKUBE_EXISTS" = "true" ]; then
    echo "Minikube cluster '$MINIKUBE_PROFILE' already exists. Starting it..."
    minikube start -p "$MINIKUBE_PROFILE" --cpus=4 --memory=8g --driver podman
else
    echo "Creating new Minikube cluster '$MINIKUBE_PROFILE' (2 nodes)..."
    minikube start -p "$MINIKUBE_PROFILE" --nodes=2 --cpus=4 --memory=8g --driver podman
fi

echo "✓ Minikube cluster ready"

log "Checking for legacy (pre-Terraform) bootstrap"

# If this cluster was bootstrapped by the old setup.sh, its ArgoCD-managed
# releases (argocd/calico/cert-manager/envoy-gateway) will collide with the
# Terraform-managed ones. Require a clean cluster in that case.
#
# Markers unique to the legacy flow:
#   - the openunison namespace
#   - the legacy ArgoCD Application objects (calico / cert-manager /
#     envoy-gateway-system*), which the new ApplicationSet never generates.
# The argocd helm release is NOT a marker: Terraform installs it too.
#
# NOTE: kubectl `get` exits 0 (empty list) even when the namespace does not
# exist, so existence must be checked on the output, not the exit code.
LEGACY=false
if kubectl get ns openunison &> /dev/null; then
    LEGACY=true
fi
if kubectl -n "$ARGO_NS" get applications.argoproj.io calico cert-manager envoy-gateway-system envoy-gateway-system-crds envoy-gateway-system-resources argocd-httproute -o name 2>/dev/null | grep -q .; then
    LEGACY=true
fi
if [ "$LEGACY" = "true" ]; then
    die "cluster '$MINIKUBE_PROFILE' still carries the legacy (pre-Terraform) bootstrap. Recreate it first: make reset"
fi

log "Terraform: init"

mkdir -p "$TF_STATE_DIR" "$TF_PLAN_DIR"
cd "$TF_DIR"
terraform init -input=false

log "Terraform: base plan (module chain up to Keycloak)"

# A FRESH cluster bootstraps in two phases. The keycloak Terraform provider
# (terraform/keycloak-sso.tf) performs its initial login during `terraform
# plan`, but it reaches Keycloak through a localhost port-forward — and the
# keycloak service only exists AFTER the keycloak module has been applied.
# Phase 1 therefore plans/applies only the module chain up to Keycloak
# (-target=module.keycloak includes its dependencies); the keycloak provider
# resources are pruned from that plan, so no login is attempted and no
# port-forward is needed. (make tf-base-plan / make tf-base-apply is the
# manual equivalent.)
terraform plan -input=false -target=module.keycloak -out="${TF_PLAN_DIR}/base.tfplan"

log "Terraform: base apply (plan/base.tfplan)"

terraform apply -input=false "${TF_PLAN_DIR}/base.tfplan"

log "Starting Keycloak port-forward (keycloak Terraform provider)"

# Keycloak is now up (the module waits for readiness). The full plan/apply
# below provisions the SSO objects (argocd OIDC client, 'groups' scope,
# GitHub identity provider, ArgoCDAdmins group) with the keycloak Terraform
# provider, which logs in through this port-forward. Stopped on exit.
bash "${REPO_ROOT}/scripts/keycloak-port-forward.sh" start
trap 'bash "${REPO_ROOT}/scripts/keycloak-port-forward.sh" stop || true' EXIT

log "Terraform: plan (saved to plan/terraform.tfplan)"

# The plan is written to a file so `terraform apply` can execute exactly
# this plan (see make tf-plan / make tf-apply for the manual workflow).
terraform plan -input=false -out="$TF_PLAN_FILE"

log "Terraform: apply (plan/terraform.tfplan)"

terraform apply -input=false "$TF_PLAN_FILE"

echo "✓ Terraform apply complete"

log "Setting up ApplicationSet"

# The ApplicationSet(s) generate the remaining ArgoCD-managed apps
# (argo-rollouts, fluent-bit, kargo, keda, kube-prometheus-stack, loki,
# http-routes). cert-manager/envoy-gateway/argocd/keycloak are now
# Terraform-managed and no longer live under deploy/argocd-applications/.
kubectl apply -f "${REPO_ROOT}/deploy/argocd-applicationsets/root.yaml"

log "Enable gateway traffic (sudo minikube tunnel)"

# The Envoy Gateway service is a LoadBalancer without an LB controller on
# minikube; 'sudo minikube tunnel' bridges its NodePort to localhost so the
# *.localhost routes work from the browser/curl. It needs sudo and runs in a
# separate terminal, so prompt the user now and let them start it while the
# ArgoCD status check below runs. The kubectl checks themselves do not need
# the tunnel; only browser/curl verification of the routes does.
# Non-interactive runs (CI, nohup, piped stdin) are skipped — the final
# banner still prints the command.
echo ""
echo "Before verifying the routes, run this in ANOTHER terminal:"
echo ""
echo "    sudo minikube tunnel -p ${MINIKUBE_PROFILE}"
echo ""
echo "Then you can check the gateway routes, e.g.:"
echo "    http://argocd.localhost     http://keycloak.localhost"
echo "    http://grafana.localhost    http://rollouts.localhost"
echo ""
if [ -t 0 ]; then
    read -r -p "Press ENTER once the tunnel is running (ENTER also skips): " _ || warn "no input available, continuing"
else
    warn "non-interactive run: start 'sudo minikube tunnel -p ${MINIKUBE_PROFILE}' manually to enable gateway traffic"
fi

# Wait for ArgoCD components to be ready
echo "Checking ArgoCD pod status..."
kubectl -n "$ARGO_NS" wait --for=condition=Ready pods --timeout=300s --all 2>/dev/null || warn "Some pods may not be ready yet"

echo ""
echo "ApplicationSet status:"
kubectl get applicationsets.argoproj.io -n "$ARGO_NS" -o wide

echo ""
log "Setup Complete"
echo "Terraform state: ${TF_STATE_DIR}/terraform.tfstate"
echo "Terraform plan:  ${TF_PLAN_FILE}"
echo "ArgoCD is running in namespace '$ARGO_NS'"
echo "ApplicationSet 'cluster-addons' has been configured"
echo ""
echo "Access the ArgoCD dashboard at:  http://argocd.localhost   (admin/admin)"
echo "Access the Keycloak console at:  http://keycloak.localhost (admin/admin)"
echo "run 'sudo minikube tunnel -p demo' to enable traffic to the Envoy Gateway"
