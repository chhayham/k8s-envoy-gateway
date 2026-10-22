output "argocd_dashboard_url" {
  description = "ArgoCD dashboard (run 'sudo minikube tunnel -p demo' first)"
  value       = "http://argocd.localhost"
}

output "argocd_admin_credentials" {
  description = "ArgoCD admin login"
  value       = "admin / admin"
}

output "keycloak_console_url" {
  description = "Keycloak admin console (run 'sudo minikube tunnel -p demo' first)"
  value       = "http://keycloak.localhost"
}

output "keycloak_admin_credentials" {
  description = "Keycloak admin login"
  value       = "${var.keycloak_admin_user} / ${var.keycloak_admin_password}"
}

output "tunnel_hint" {
  description = "Gateway traffic hint"
  value       = "run 'sudo minikube tunnel -p demo' to enable traffic to the Envoy Gateway"
}
