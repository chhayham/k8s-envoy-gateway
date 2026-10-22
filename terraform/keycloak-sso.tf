# Keycloak SSO configuration for ArgoCD — managed by the keycloak Terraform
# provider (https://github.com/keycloak/terraform-provider-keycloak,
# Keycloak 26.x only), replacing the old in-cluster 'keycloak-github-idp'
# provisioning Job.
#
# Provisions in the 'master' realm:
#   - 'argocd' public OIDC client (authorization code + PKCE S256) with the
#     redirect URIs ArgoCD's UI/CLI need
#   - 'groups' client scope with a Group-Membership mapper (token claim
#     'groups', full path off) and an 'argocd-username' client scope with a
#     Hardcoded-Claim mapper (token claim 'email' = the demo username, for the
#     ArgoCD 3.x display username), both attached as default scopes on the
#     client
#   - 'github' identity provider (GitHub SSO) — only when credentials are
#     present in terraform/terraform.auto.tfvars
#   - 'ArgoCDAdmins' group + the demo admin user (realm roles 'admin' and
#     'default-roles-master', group membership) — ArgoCD RBAC maps
#     'ArgoCDAdmins' to role:admin
#   - a custom 'sso first broker login' flow (create-or-auto-link, no local
#     password) assigned to the GitHub IdP via first_broker_login_flow_alias,
#     replacing the unusable built-in flow for the passwordless demo user
#
# Connectivity: Terraform runs on this machine and the Keycloak service is a
# ClusterIP, so the provider talks to Keycloak through a localhost
# port-forward (scripts/keycloak-port-forward.sh). setup.sh and the make
# tf-plan/tf-apply targets start it automatically.
# null_resource.keycloak_ready waits for the API (discovery endpoint) before
# any provider resource is created, replacing the Job's retry-on-unavailable
# behaviour.

provider "keycloak" {
  alias     = "sso"
  url       = var.keycloak_sso_address
  client_id = "admin-cli"
  username  = var.keycloak_admin_user
  password  = var.keycloak_admin_password
}

data "keycloak_realm" "master" {
  provider = keycloak.sso
  realm    = "master"
}

# Gate every provider resource on the Keycloak API being reachable. Fresh
# clusters take several minutes (image pulls + PostgreSQL init).
resource "null_resource" "keycloak_ready" {
  depends_on = [module.keycloak]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for the Keycloak API at ${var.keycloak_sso_address} ..."
      for i in $(seq 1 120); do
        if curl -fsS "${var.keycloak_sso_address}/realms/master/.well-known/openid-configuration" > /dev/null 2>&1; then
          echo "Keycloak API is ready"
          exit 0
        fi
        sleep 5
      done
      echo "Keycloak API not ready after 10 minutes. Check 'kubectl -n keycloak get pods' and the port-forward log terraform/state/keycloak-pf.log" >&2
      exit 1
    EOT
  }
}

# --- first broker login flow (custom, per-IdP) ------------------------------
#
# Keycloak's built-in 'first broker login' flow cannot complete for the
# passwordless demo user: 'idp-confirm-link' / 'idp-username-password-form'
# require a local password (always fails with 'invalid_user_credentials'), and
# with those disabled the flow falls through to the 'Conditional 2FA' branch,
# whose condition check NPEs on the null session user (KC 26 bug:
# OTPFormAuthenticator.configuredFor has no null check). Keycloak also refuses
# to add executions to built-in flows via the admin API, so instead a minimal
# custom flow is defined here and assigned to the GitHub identity provider via
# 'first_broker_login_flow_alias' — a per-IdP setting Keycloak honors in
# preference to the realm default:
#
#   idp-create-user-if-unique (ALTERNATIVE) - registers new users and sets
#                                             them as the session user; for
#                                             an existing one records it in
#                                             the session and falls through
#   idp-auto-link             (ALTERNATIVE) - links the IdP identity to the
#                                             existing user and sets the
#                                             session user — no password, no
#                                             confirmation form
#
# Both steps are ALTERNATIVE elements of a single flat flow (first success
# wins): a new GitHub identity is created by step 1, an existing one is
# linked by step 2 after step 1 has recorded it. They MUST NOT be mixed
# with REQUIRED elements in the same flow — the flow engine silently
# ignores ALTERNATIVE executions that share a flow level with REQUIRED
# ones (warning 'REQUIRED and ALTERNATIVE elements at same level'), which
# drops the create/link steps and fails with UNKNOWN_USER ('Invalid
# username or password'). The built-in flow avoids this with a 'User
# creation or linking' sub-flow, but the keycloak Terraform provider (5.x)
# cannot express sub-flows, hence the flat alternatives-only shape.
# (idp-review-profile is deliberately omitted: on success it ends the flow
# before any user is set.)
#
# The demo user's first GitHub login therefore just links 'github' to the
# pre-created user; later logins skip the flow entirely (identity already
# linked).

resource "keycloak_authentication_flow" "sso_first_broker_login" {
  provider    = keycloak.sso
  depends_on  = [null_resource.keycloak_ready]
  realm_id    = data.keycloak_realm.master.id
  alias       = "sso first broker login"
  description = "Passwordless first GitHub SSO login: create the user if unique, otherwise auto-link the existing one (no local password required)"
}

resource "keycloak_authentication_execution" "create_user_if_unique" {
  provider          = keycloak.sso
  depends_on        = [keycloak_authentication_flow.sso_first_broker_login]
  realm_id          = data.keycloak_realm.master.id
  parent_flow_alias = keycloak_authentication_flow.sso_first_broker_login.alias
  authenticator     = "idp-create-user-if-unique"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_execution" "autolink" {
  provider          = keycloak.sso
  depends_on        = [keycloak_authentication_flow.sso_first_broker_login, keycloak_authentication_execution.create_user_if_unique]
  realm_id          = data.keycloak_realm.master.id
  parent_flow_alias = keycloak_authentication_flow.sso_first_broker_login.alias
  authenticator     = "idp-auto-link"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

# --- argocd OIDC client ---------------------------------------------------

resource "keycloak_openid_client" "argocd" {
  provider   = keycloak.sso
  depends_on = [null_resource.keycloak_ready]

  realm_id  = data.keycloak_realm.master.id
  client_id = "argocd"
  name      = "ArgoCD"
  enabled   = true

  access_type                = "PUBLIC"
  standard_flow_enabled      = true
  service_accounts_enabled   = false
  pkce_code_challenge_method = "S256"

  root_url  = "http://argocd.localhost"
  admin_url = "http://argocd.localhost"
  valid_redirect_uris = [
    "http://argocd.localhost/auth/callback", # argocd CLI
    "http://argocd.localhost/pkce/verify",   # argocd UI
    "http://localhost:8085/auth/callback",   # argocd CLI --sso-login
  ]
  web_origins = ["http://argocd.localhost"]
}

# --- 'groups' client scope -> token 'groups' claim ------------------------

resource "keycloak_openid_client_scope" "groups" {
  provider    = keycloak.sso
  depends_on  = [null_resource.keycloak_ready]
  realm_id    = data.keycloak_realm.master.id
  name        = "groups"
  description = "adds the groups claim (group membership) to tokens"
}

resource "keycloak_openid_group_membership_protocol_mapper" "argocd_groups" {
  provider        = keycloak.sso
  depends_on      = [keycloak_openid_client_scope.groups]
  realm_id        = data.keycloak_realm.master.id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
}

# --- display-username client scope -------------------------------------------
#
# ArgoCD 3.x removed 'usernameClaim'/'userIDClaim' from oidc.config; for SSO
# logins the username shown in the UI is hardcoded in argocd-server
# (util/session/sessionmanager.go, Username()): for an IdP-signed token it is
# the 'email' claim when present, else 'federated_claims.user_id', else 'sub'
# (the Keycloak user UUID). The demo user has no email address, and no
# standard Keycloak 26 mapper can synthesize the nested 'federated_claims'
# claim (the claim-to-claim mapper was removed in KC 26 and the script-based
# mapper needs the 'scripts' feature, which is disabled on this deployment),
# so the username is exposed through the 'email' claim instead, via a
# hardcoded-claim mapper on the 'argocd' client. A user-attribute mapper
# would be the multi-user-correct way, but the keycloak provider (v5.x)
# cannot persist keycloak_user 'attributes' on update (its refresh reads them
# back empty and the update PUT drops them, so the attribute never lands),
# hence the hardcoded value - kept in sync with the username through the same
# var.argocd_admin_username. RBAC is unaffected - ArgoCD policy matching uses
# the 'sub'-based user identifier, not the display name.

resource "keycloak_openid_client_scope" "argocd_username" {
  provider    = keycloak.sso
  depends_on  = [null_resource.keycloak_ready]
  realm_id    = data.keycloak_realm.master.id
  name        = "argocd-username"
  description = "exposes the username as the 'email' claim (ArgoCD 3.x display username)"
}

resource "keycloak_openid_hardcoded_claim_protocol_mapper" "argocd_username" {
  provider         = keycloak.sso
  depends_on       = [keycloak_openid_client_scope.argocd_username]
  realm_id         = data.keycloak_realm.master.id
  client_scope_id  = keycloak_openid_client_scope.argocd_username.id
  name             = "argocd-username"
  claim_name       = "email"
  claim_value      = var.argocd_admin_username
  add_to_id_token  = true
}

# Full default scope list for the argocd client: the standard set a fresh
# Keycloak 26 client gets (web-origins, acr, roles, profile, basic, email)
# plus 'groups' (ArgoCD RBAC) and 'argocd-username' (ArgoCD display
# username). Keycloak replaces the list wholesale when it is set.
resource "keycloak_openid_client_default_scopes" "argocd" {
  provider       = keycloak.sso
  depends_on     = [keycloak_openid_client.argocd, keycloak_openid_client_scope.groups, keycloak_openid_client_scope.argocd_username]
  realm_id       = data.keycloak_realm.master.id
  client_id      = keycloak_openid_client.argocd.id
  default_scopes = ["web-origins", "acr", "roles", "profile", "basic", "email", "groups", "argocd-username"]
}

# --- GitHub identity provider ----------------------------------------------
# Created only when credentials are present (see
# terraform/terraform.auto.tfvars.example).

resource "keycloak_oidc_github_identity_provider" "github" {
  provider   = keycloak.sso
  depends_on = [null_resource.keycloak_ready]

  count = var.github_client_id == "" ? 0 : 1

  realm        = "master"
  alias        = "github"
  enabled      = true
  display_name = "GitHub"
  store_token  = true
  trust_email  = true
  # Use the custom passwordless first-login flow (defined above) instead of
  # the realm's built-in 'first broker login' — see the comment block there.
  first_broker_login_flow_alias = keycloak_authentication_flow.sso_first_broker_login.alias
  client_id                     = var.github_client_id
  client_secret                 = var.github_client_secret
}

# --- admin user + ArgoCDAdmins group ----------------------------------------

resource "keycloak_group" "argocd_admins" {
  provider   = keycloak.sso
  depends_on = [null_resource.keycloak_ready]
  realm_id   = data.keycloak_realm.master.id
  name       = "ArgoCDAdmins"
}

resource "keycloak_user" "argocd_admin" {
  provider   = keycloak.sso
  depends_on = [null_resource.keycloak_ready]
  realm_id   = data.keycloak_realm.master.id
  username   = var.argocd_admin_username
  enabled    = true
  # NOTE: do not add user 'attributes' here - the keycloak provider (v5.x)
  # cannot persist them on update (see the 'argocd-username' scope's comment
  # for how the display username is provided instead).
}

data "keycloak_role" "admin" {
  provider = keycloak.sso
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

data "keycloak_role" "default_roles" {
  provider = keycloak.sso
  realm_id = data.keycloak_realm.master.id
  name     = "default-roles-master"
}

resource "keycloak_user_roles" "argocd_admin" {
  provider   = keycloak.sso
  depends_on = [keycloak_user.argocd_admin, data.keycloak_role.admin, data.keycloak_role.default_roles]
  realm_id   = data.keycloak_realm.master.id
  user_id    = keycloak_user.argocd_admin.id
  role_ids   = [data.keycloak_role.admin.id, data.keycloak_role.default_roles.id]
}

resource "keycloak_user_groups" "argocd_admin" {
  provider   = keycloak.sso
  depends_on = [keycloak_user.argocd_admin, keycloak_group.argocd_admins]
  realm_id   = data.keycloak_realm.master.id
  user_id    = keycloak_user.argocd_admin.id
  group_ids  = [keycloak_group.argocd_admins.id]
}
