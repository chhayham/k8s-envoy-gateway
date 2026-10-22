# Cluster bootstrap modules.
#
# Dependency chain (required ordering):
#
#   gateway-api  <  cert-manager  <  envoy-gateway  <  keycloak  <  argocd
#
#   - cert-manager needs the Gateway API CRDs (config.gatewayAPI.enabled)
#   - envoy-gateway needs cert-manager for listener certificates
#   - keycloak is exposed through the Envoy Gateway
#   - argocd is the last piece of the control plane
#
# The CNI is provided by minikube itself (kindnet on the podman driver);
# we deliberately do NOT deploy a second CNI (a Calico + kindnet
# coexistence corrupts cross-node pod routing).
# The KEDA CRDs are installed independently of the chain.

module "keda" {
  source = "./modules/keda"
}

module "gateway-api" {
  source = "./modules/gateway-api"
}

module "cert-manager" {
  source     = "./modules/cert-manager"
  depends_on = [module.gateway-api]
}

module "envoy-gateway" {
  source     = "./modules/envoy-gateway"
  depends_on = [module.cert-manager]
}

module "keycloak" {
  source     = "./modules/keycloak"
  depends_on = [module.envoy-gateway]

  admin_user        = var.keycloak_admin_user
  admin_password    = var.keycloak_admin_password
  postgres_password = var.keycloak_postgres_password
}

module "argocd" {
  source     = "./modules/argocd"
  depends_on = [module.keycloak]
}
