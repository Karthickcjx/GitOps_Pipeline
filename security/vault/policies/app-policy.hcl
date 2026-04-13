# =============================================================================
# Vault Policies
# =============================================================================
# HashiCorp Vault policies for least-privilege secret access.
# Each service gets its own policy scoped to its secret path.
# =============================================================================

# ── App Policy ──────────────────────────────────────────────────────────────
# Read-only access to application secrets
path "secret/data/gitops-platform/*/my-app/*" {
  capabilities = ["read"]
}

path "secret/metadata/gitops-platform/*/my-app/*" {
  capabilities = ["list", "read"]
}

# ── CI/CD Policy ────────────────────────────────────────────────────────────
# Allows CI to read deployment secrets
path "secret/data/gitops-platform/*/deploy/*" {
  capabilities = ["read"]
}

# ── Monitoring Policy ───────────────────────────────────────────────────────
# Alertmanager needs Slack webhook and OpsGenie key
path "secret/data/gitops-platform/monitoring/*" {
  capabilities = ["read"]
}

# ── Admin Policy ────────────────────────────────────────────────────────────
# Full management of gitops-platform secrets
path "secret/data/gitops-platform/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/gitops-platform/*" {
  capabilities = ["list", "read", "delete"]
}

path "sys/policies/acl/*" {
  capabilities = ["read", "list"]
}
