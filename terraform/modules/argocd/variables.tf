variable "namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd chart version"
  type        = string
  default     = "10.9.2"
}
