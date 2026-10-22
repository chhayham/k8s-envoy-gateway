# Both providers use the *current* kubeconfig context.
# scripts/setup.sh guarantees the minikube 'demo' context is current
# (`minikube start -p demo` switches current-context for you).
# Both providers are pinned to the minikube 'demo' context explicitly.
# NOTE: neither the kubernetes provider's embedded kubernetes_manifest
# resource nor the helm provider auto-discover ~/.kube/config or $KUBECONFIG
# without an explicit config_path — set it on both.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}
