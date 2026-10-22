# KEDA CRDs (v2.21.0).
#
# Only the CRDs are Terraform-managed; the KEDA operator itself remains
# ArgoCD-managed (deploy/argocd-applications/keda/config.yaml).
#
# Replaces the legacy `kubectl apply` of the release artifact in
# scripts/setup.sh. The CRDs are vendored (one file per
# CustomResourceDefinition under crds/) from:
#   https://github.com/kedacore/keda/releases/download/v2.21.0/keda-2.21.0-crds.yaml
# so the bootstrap has no runtime network dependency.
resource "kubernetes_manifest" "crd" {
  for_each = toset(fileset("${path.module}/crds", "*.yaml"))
  manifest = yamldecode(file("${path.module}/crds/${each.key}"))
}
