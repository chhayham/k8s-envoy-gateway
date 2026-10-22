variable "namespace" {
  description = "Namespace for the Envoy Gateway controller and the cluster Gateway"
  type        = string
  default     = "envoy-gateway-system"
}

variable "chart_version" {
  description = "gateway-helm chart version (must match the gateway-api CRDs version)"
  type        = string
  default     = "v1.9.1"
}

variable "gateway_class_name" {
  description = "GatewayClass name referenced by HTTPRoutes (indirectly, via the Gateway)"
  type        = string
  default     = "envoy"
}

variable "gateway_name" {
  description = "Cluster Gateway name referenced by all HTTPRoutes"
  type        = string
  default     = "envoy-gateway"
}
