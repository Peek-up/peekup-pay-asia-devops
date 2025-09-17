# Read system health check
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# Manage secrets engines (mounts)
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# --- CORRECTED KV v2 PERMISSIONS ---

# Allow full CRUDL access to the secret data.
path "kv/data/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# --- THE FIX ---
# Allow full CRUDL access to the secret metadata.
# The "read" capability is CRUCIAL for viewing version history.
path "kv/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}