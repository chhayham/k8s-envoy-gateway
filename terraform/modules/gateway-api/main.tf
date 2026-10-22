# Gateway API + Envoy Gateway CRDs, vendored one file per resource.
#
# Replaces:
#   - the 'envoy-gateway-system-crds' ArgoCD app
#     (deploy/argocd-applications/envoy-gateway-system/crds-config.yaml)
#
# Why not the upstream envoyproxy/gateway-crds-helm chart: it renders ~3.9 MB
# of CRDs as helm templates, which overflows helm's 1 MiB release-Secret
# limit ("Secret ... is invalid: data: Too long"). The files under crds/ are
# the exact rendered output of that chart (v1.9.1, channel=experimental,
# crds.envoyGateway.enabled=true), applied with kubernetes_manifest instead.
# CustomResourceDefinition and ValidatingAdmissionPolicy are core kinds, so
# plan-time API validation works even on a fresh cluster.
#
# To bump the version: re-run
#   helm pull oci://registry-1.docker.io/envoyproxy/gateway-crds-helm --version <v>
#   helm template <chart> --set crds.gatewayAPI.enabled=true \
#     --set crds.gatewayAPI.channel=experimental --set crds.envoyGateway.enabled=true
# and re-split the output (see scripts/ or the module history).
#
# Must be installed before cert-manager (gatewayAPI injector) and before the
# Envoy Gateway controller — see terraform/main.tf for the dependency chain.
resource "kubernetes_manifest" "crd" {
  for_each = toset(fileset("${path.module}/crds", "*.yaml"))
  manifest = yamldecode(file("${path.module}/crds/${each.key}"))
}
