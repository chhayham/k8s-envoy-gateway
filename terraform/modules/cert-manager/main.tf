# cert-manager (helm) plus the bootstrap issuer/CA resources that previously
# lived in deploy/argocd-applications/cert-manager/resources/manifest.yaml.
#
# Replaces:
#   - deploy/argocd-applications/cert-manager/config.yaml (ArgoCD app)
#   - deploy/argocd-applications/cert-manager/resources/manifest.yaml
#     (ClusterIssuers/Certificate, now applied directly by terraform)
#
# config.gatewayAPI.enabled requires the Gateway API CRDs, which is why this
# module depends on module.gateway-api (see terraform/main.tf).
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = var.namespace
  create_namespace = true
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  version          = var.chart_version
  wait             = true
  values = [
    yamlencode({
      installCRDs = true
      resources = {
        limits   = { cpu = "200m", memory = "256Mi" }
        requests = { cpu = "100m", memory = "128Mi" }
      }
      config = {
        gatewayAPI = {
          enabled = true
        }
      }
    }),
  ]
}

# Bootstrap issuers + root CA, packaged as a minimal local chart.
#
# kubernetes_manifest validates CRD-backed kinds against the live API at plan
# time, which fails on a fresh cluster before the cert-manager CRDs exist
# (deferral for this case is experimental-only in stable Terraform). A
# helm_release has no plan-time kind validation, and depends_on guarantees
# the CRDs are installed before this chart is applied.
#
# Note: helm creates the Certificate before the ClusterIssuers (alphabetical
# order); cert-manager reconciles it as soon as the issuers appear.
resource "helm_release" "bootstrap" {
  name             = "cert-manager-bootstrap"
  namespace        = var.namespace
  create_namespace = false
  chart            = "${path.root}/charts/cert-manager-bootstrap"
  wait             = true
  depends_on       = [helm_release.cert_manager]
}
