# Envoy Gateway controller + the cluster GatewayClass/Gateway.
#
# Replaces:
#   - deploy/argocd-applications/envoy-gateway-system/gw-config.yaml (ArgoCD app)
#   - deploy/argocd-applications/envoy-gateway-system/resources/resource-manifest.yaml
#     (GatewayClass/Gateway, now applied directly by terraform)
#
# The Envoy Gateway CRDs are rendered by the chart itself (crds.enabled); the
# Gateway API CRDs come from module.gateway-api.
#
# OpenUnison-specific listeners ('ou-https', 'kube-oidc-proxy') and the
# ReferenceGrant were removed together with OpenUnison. There is intentionally
# no generic HTTPS listener: add one together with a cert-manager Certificate
# when a generic TLS endpoint is needed.
resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  namespace        = var.namespace
  create_namespace = true
  repository       = "oci://registry-1.docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = var.chart_version
  wait             = true
  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      config = {
        envoyGateway = {
          gateway = {
            controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
          }
          provider = {
            type = "Kubernetes"
          }
          logging = {
            level = { default = "info" }
          }
          extensionApis = {
            enableBackend = true
          }
        }
      }
    }),
  ]
}

# Cluster GatewayClass/Gateway, packaged as a minimal local chart.
#
# kubernetes_manifest validates CRD-backed kinds against the live API at plan
# time, which fails on a fresh cluster before the Gateway API CRDs exist
# (deferral for this case is experimental-only in stable Terraform). A
# helm_release has no plan-time kind validation, and depends_on guarantees
# the controller and CRDs exist before this chart is applied.
#
# Note: helm creates the Gateway before the GatewayClass (alphabetical
# order); the Envoy Gateway controller reconciles it once the class exists.
resource "helm_release" "gateway_config" {
  name             = "envoy-gateway-config"
  namespace        = var.namespace
  create_namespace = false
  chart            = "${path.root}/charts/envoy-gateway-config"
  wait             = true
  values = [
    yamlencode({
      gatewayClassName = var.gateway_class_name
      gatewayName      = var.gateway_name
    }),
  ]
  depends_on = [helm_release.envoy_gateway]
}
