variable "kubeconfig_path" {
  description = "Path to the kubeconfig file (used by the kubernetes/helm providers)"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use (the minikube profile)"
  type        = string
  default     = "demo"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin console user"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin console password (demo default)"
  type        = string
  default     = "admin"
}

variable "keycloak_postgres_password" {
  description = "Password for the bundled Keycloak PostgreSQL instance"
  type        = string
  default     = "admin"
}

variable "keycloak_sso_address" {
  description = "Keycloak base URL for the keycloak Terraform provider (localhost port-forward managed by scripts/keycloak-port-forward.sh)"
  type        = string
  default     = "http://localhost:18082"
}

variable "argocd_admin_username" {
  description = "Keycloak username that gets ArgoCD admin access (the first GitHub SSO login links to it)"
  type        = string
  default     = "chhayham"
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID for the Keycloak GitHub identity provider (leave empty to skip creating the IdP; set in terraform.auto.tfvars)"
  type        = string
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret for the Keycloak GitHub identity provider (set in terraform.auto.tfvars)"
  type        = string
  sensitive   = true
  default     = ""
}
