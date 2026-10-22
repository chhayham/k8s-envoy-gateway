# ArgoCD — last step in the bootstrap chain.
#
# Replaces the legacy `helm upgrade --install argocd` in scripts/setup.sh
# (values moved from deploy/argocd/values.yaml to values.yaml next to this
# file). The ApplicationSet(s) in deploy/argocd-applicationsets/root.yaml are
# applied by scripts/setup.sh after this release is ready.
#
# The OIDC issuer is the browser-reachable host name `keycloak.localhost`
# (served through the Envoy Gateway). Inside the cluster that host name does
# not resolve, so the argocd-server pod maps it to the Keycloak service's
# ClusterIP via hostAliases — merged into the static values below.
data "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "keycloak"
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  wait             = true
  values = [yamlencode(merge(
    yamldecode(file("${path.module}/values.yaml")),
    {
      global = {
        hostAliases = [
          {
            ip        = data.kubernetes_service.keycloak.spec[0].cluster_ip
            hostnames = ["keycloak.localhost"]
          },
        ],
      },
    },
  ))]
}
