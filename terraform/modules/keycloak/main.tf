# Keycloak (Bitnami chart) with the bundled PostgreSQL instance.
#
# Replaces OpenUnison as the demo's identity provider. Exposed at
# http://keycloak.localhost through the Envoy Gateway via
# deploy/httproute/keycloak/keycloak-httproute.yaml (synced by the
# cluster-addons-httproute ApplicationSet), so the Service stays a ClusterIP.
resource "helm_release" "keycloak" {
  name             = "keycloak"
  namespace        = var.namespace
  create_namespace = true
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = var.chart_version
  # The base phase (plan/base.tfplan, -target=module.keycloak) is applied
  # FIRST on a fresh cluster and must leave Keycloak READY: the next phase's
  # keycloak provider performs its initial login during `terraform plan` and
  # fails fast if the API is not reachable yet. Keycloak + PostgreSQL are
  # slow to become ready on first start (image pulls + database init), hence
  # the generous timeout.
  wait    = true
  timeout = 900
  values = [
    yamlencode({
      auth = {
        adminUser     = var.admin_user
        adminPassword = var.admin_password
      }
      # Bitnami moved the versioned image tags off docker.io/bitnami (only
      # digest-named tags are published there now); the legacy tags live
      # under docker.io/bitnamilegacy. Point the keycloak image (incl. its
      # init container) and the bundled PostgreSQL subchart there, and skip
      # the chart's standard-container verification, which only recognizes
      # bitnami/* repositories.
      global = {
        security = {
          allowInsecureImages = true
        }
      }
      image = {
        repository = "bitnamilegacy/keycloak"
      }
      postgresql = {
        enabled = true
        image   = { repository = "bitnamilegacy/postgresql" }
        # The PVC is created root:root 0755 and fsGroup only sets group
        # ownership, so the non-root postgres container (uid 1001) cannot
        # initialize the data directory without a root chown first.
        volumePermissions = {
          enabled = true
          image   = { repository = "bitnamilegacy/os-shell" }
        }
        auth = {
          postgresPassword = var.postgres_password
          database         = "keycloak"
          username         = "keycloak"
        }
        primary = {
          persistence = {
            enabled = true
            size    = "2Gi"
          }
        }
      }
      service = {
        type  = "ClusterIP"
        ports = { http = 80 }
      }
      ingress = {
        enabled = false
      }
      resources = {
        limits   = { cpu = "1000m", memory = "1Gi" }
        requests = { cpu = "250m", memory = "512Mi" }
      }
    }),
  ]
}
