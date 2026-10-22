terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # 3.x required: 2.38.0 has a kubernetes_manifest client-config bug
      # (GH-2788, fixed in 3.0.0) that breaks default kubeconfig discovery.
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    keycloak = {
      # Keycloak 26.x-only provider: provisions the SSO objects in the
      # 'master' realm (see keycloak-sso.tf).
      source  = "keycloak/keycloak"
      version = "~> 5.10"
    }
  }

  # Terraform state is stored locally on this machine (not in a remote
  # backend): terraform/state/terraform.tfstate
  backend "local" {
    path = "state/terraform.tfstate"
  }
}
