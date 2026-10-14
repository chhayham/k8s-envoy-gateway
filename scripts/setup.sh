#!/bin/bash
# Idempotent script for ArgoCD bootstrap
# This script deploys ArgoCD and sets up the ApplicationSet

set -e  # Fail fast on errors

echo "=== Checking prerequisites ==="

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed or not in PATH"
    exit 1
fi

echo "✓ podman found: $(podman --version)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

echo "✓ kubectl found: $(kubectl version --client | grep "Client" | awk -F': ' '{print $2}' 2>/dev/null || echo 'version unknown')"

# Check if minikube is available
if ! command -v minikube &> /dev/null; then
    echo "ERROR: minikube is not installed or not in PATH"
    exit 1
fi

echo "✓ minikube found: $(minikube version | grep version | head -1)"

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed or not in PATH"
    exit 1
fi

echo "✓ helm found: $(helm version --short)"

# Check if minikube cluster exists
MINIKUBE_EXISTS=false
if minikube status -p demo &> /dev/null; then
    MINIKUBE_EXISTS=true
fi

echo ""
echo "=== Setting up Minikube Cluster ==="

# OpenUnison OIDC configuration for the Kubernetes API server.
# The kube-apiserver acts as an OIDC relying party for OpenUnison's built-in
# K8s IdP (https://k8sou.localhost/auth/idp/k8sIdp) so that tokens minted by
# kube-oidc-proxy (k8sapi.localhost) are accepted.
OIDC_ISSUER_URL="https://k8sou.localhost/auth/idp/k8sIdp"
MINIKUBE_OIDC_ARGS=(
    "--extra-config=apiserver.oidc-issuer-url=${OIDC_ISSUER_URL}"
    "--extra-config=apiserver.oidc-client-id=kubernetes"
    "--extra-config=apiserver.oidc-username-claim=sub"
    "--extra-config=apiserver.oidc-groups-claim=groups"
)

if [ "$MINIKUBE_EXISTS" = "true" ]; then
    # API server extra-config is baked in at cluster creation time and cannot
    # be changed on an existing cluster.
    if minikube ssh -p demo -- ps -ef 2>/dev/null | grep kube-apiserver | grep -q 'oidc-issuer-url'; then
        echo "Minikube cluster 'demo' already exists (OIDC configured). Starting it..."
        minikube start -p demo --cpus=4 --memory=8g --driver podman
    else
        echo "ERROR: cluster 'demo' exists but kube-apiserver was started WITHOUT the"
        echo "       OpenUnison OIDC flags (--oidc-issuer-url, --oidc-client-id, ...)."
        echo "       extra-config is only applied at cluster creation time. Recreate it:"
        echo "           minikube delete -p demo && ./scripts/setup.sh    (or: make reset)"
        exit 1
    fi
else
    echo "Creating new Minikube cluster 'demo' with 2 nodes + OpenUnison OIDC..."
    minikube start -p demo --nodes=2 --cpus=4 --memory=8g --driver podman "${MINIKUBE_OIDC_ARGS[@]}"
fi

echo "✓ Minikube cluster ready"

# Template Calico CRDs and install CRDs
echo ""
echo "=== Deploying Calico CRDs ==="
CALICO_CRDS_VERSION=v3.33.0
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm repo update
# kubectl create namespace tigera-operator --dry-run=client -o yaml | kubectl apply -f -
# helm template calico-crds projectcalico/projectcalico.org.v3 --version $CALICO_CRDS_VERSION --api-versions admissionregistration.k8s.io/v1beta1/MutatingAdmissionPolicy --output-dir deploy/argocd-applications/calico/crds
helm template calico-crds projectcalico/projectcalico.org.v3 --version $CALICO_CRDS_VERSION --api-versions admissionregistration.k8s.io/v1/MutatingAdmissionPolicy | kubectl apply --server-side -f -

# Install KEDA CRDs
echo ""
echo "=== Deploying KEDA CRDs ==="
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.21.0/keda-2.21.0-crds.yaml?raw=true

echo ""
echo "=== Deploying ArgoCD ==="
# Deploy ArgoCD using Helm
ARGO_NS="argocd"
echo "Deploying ArgoCD via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm upgrade --install argocd argo/argo-cd \
    --version 10.9.2 \
    --namespace "$ARGO_NS" \
    --create-namespace \
    -f deploy/argocd/values.yaml \
    --set "configs.clusterCredentials.in-cluster.annotations.metadata\\.demo\\.io/ghapp-client-secret=${GITHUB_SECRET_ID}" \
    --wait

echo "✓ ArgoCD deployed"

echo ""
echo "=== Setting up ApplicationSet ==="

# Check if ApplicationSet exists and decide whether to edit or apply
if kubectl get applicationsets.argoproj.io cluster-addons -n "$ARGO_NS" --no-headers &> /dev/null; then
    echo "ApplicationSet 'cluster-addons' already exists in namespace '$ARGO_NS'"
else
    echo "ApplicationSet 'cluster-addons' not found - creating from manifest..."
    kubectl apply -f deploy/argocd-applicationsets/root.yaml
    kubectl apply -f deploy/argocd-applicationsets/openunison.yaml
fi

# Wait for ArgoCD components to be ready
echo "Checking ArgoCD pod status..."
kubectl -n "$ARGO_NS" wait --for=condition=Ready pods --timeout=120s --all 2>/dev/null || echo "Warning: Some pods may not be ready yet"

echo ""
echo "ApplicationSet status:"
kubectl get applicationsets.argoproj.io cluster-addons -n "$ARGO_NS" -o wide


echo ""
echo "Deploying Openunison secret..."
# dependancy:  export GITHUB_CLIENT_SECRET=***
kubectl create namespace openunison 2>/dev/null || kubectl get namespace openunison
kubectl apply -f tmp/openunison/resources/manifest.yaml --dry-run=client -o yaml | envsubst | kubectl apply -f -


echo ""
echo "=== Wiring OpenUnison OIDC (in-cluster name resolution + CA) ==="
# glibc resolves *.localhost to 127.0.0.1 (built-in, before DNS) both inside
# pods and inside the minikube VM. Without an explicit alias, kube-oidc-proxy
# dials 127.0.0.1:443 for the IdP and the kube-apiserver cannot validate
# OpenUnison-issued tokens. We point k8sou.localhost at the Envoy
# LoadBalancer service ClusterIP, which serves the IdP via the 'ou-https'
# listener with ou-tls-certificate (the exact cert the proxy trusts).
# The installed OpenUnison charts do not implement a 'host_aliases' value,
# so the proxy deployment needs an explicit hostAliases patch.

# 1) Wait for the OpenUnison IdP certificate (created by check-certs cronjob)
OU_CERT_B64=""
for i in $(seq 1 30); do
    OU_CERT_B64=$(kubectl -n openunison get secret ou-tls-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
    [ -n "$OU_CERT_B64" ] && break
    echo "waiting for openunison/ou-tls-certificate... ($i/30)"
    sleep 10
done

if [ -z "$OU_CERT_B64" ]; then
    echo "WARNING: openunison/ou-tls-certificate not found after 5m."
    echo "         Once OpenUnison is synced, re-run this script to wire OIDC."
else
    # 2) Resolve the Envoy LoadBalancer ClusterIP (stable label selector)
    ENVOY_LB_IP=$(kubectl -n envoy-gateway-system get svc \
        -l gateway.envoyproxy.io/owning-gateway-name=envoy-gateway \
        -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)

    if [ -z "$ENVOY_LB_IP" ]; then
        echo "WARNING: envoy LoadBalancer service not found. Skipping OIDC wiring."
    else
        echo "k8sou.localhost -> ${ENVOY_LB_IP} (envoy LoadBalancer ClusterIP)"

        # 3) minikube VM /etc/hosts (kube-apiserver runs inside the VM)
        minikube ssh -p demo -- sudo bash -c \
            "grep -v 'k8sou\.localhost' /etc/hosts > /tmp/.hosts.ou && echo '${ENVOY_LB_IP} k8sou.localhost' >> /tmp/.hosts.ou && cat /tmp/.hosts.ou > /etc/hosts && rm -f /tmp/.hosts.ou" \
            || echo "WARNING: could not update minikube VM /etc/hosts (sudo?)"

        # 4) Install the IdP cert into the VM system trust store so the
        #    kube-apiserver can validate the self-signed issuer
        minikube ssh -p demo -- sudo bash -c \
            "echo '${OU_CERT_B64}' | base64 -d > /usr/local/share/ca-certificates/openunison-k8sou.pem && /usr/sbin/update-ca-certificates" \
            || echo "WARNING: could not install OIDC CA into minikube VM trust store"

        # 5) hostAliases for kube-oidc-proxy (chart has no host_aliases support)
        PROXY_DEPLOY=$(kubectl -n openunison get deploy -l app=kube-oidc-proxy-orchestra -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [ -n "$PROXY_DEPLOY" ]; then
            kubectl -n openunison patch deployment "$PROXY_DEPLOY" --type json \
                -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[{\"ip\":\"${ENVOY_LB_IP}\",\"hostnames\":[\"k8sou.localhost\"]}]}]" \
                || kubectl -n openunison patch deployment "$PROXY_DEPLOY" --type json \
                -p "[{\"op\":\"add\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[{\"ip\":\"${ENVOY_LB_IP}\",\"hostnames\":[\"k8sou.localhost\"]}]}" \
                || echo "WARNING: could not patch ${PROXY_DEPLOY} hostAliases"
            echo "patched ${PROXY_DEPLOY} hostAliases -> ${ENVOY_LB_IP}"
        else
            echo "WARNING: kube-oidc-proxy deployment not found (OpenUnison not synced yet?)"
            echo "         Re-run this script once the openunison app is Healthy/Synced."
        fi
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo "ArgoCD is running in namespace '$ARGO_NS'"
echo "ApplicationSet 'cluster-addons' has been configured"
echo ""
echo "Access the ArgoCD dashboard at: http://argocd.localhost"
echo "Username: admin"
echo "Password: admin" 
echo "run 'sudo minikube tunnel -p demo' to enable traffic to envoy-gateway"