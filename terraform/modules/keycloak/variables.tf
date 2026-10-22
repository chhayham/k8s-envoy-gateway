variable "namespace" {
  description = "Namespace for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "chart_version" {
  description = "Bitnami keycloak chart version"
  type        = string
  default     = "25.2.0"
}

variable "admin_user" {
  description = "Keycloak admin console user"
  type        = string
}

variable "admin_password" {
  description = "Keycloak admin console password"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "Password for the bundled PostgreSQL instance"
  type        = string
  sensitive   = true
}
