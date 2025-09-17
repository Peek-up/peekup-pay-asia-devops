#!/usr/bin/env bash
set -e

# --- DEBUG STEP ---
echo "--- Listing contents of /app directory ---"
ls -l /app
echo "-----------------------------------------"

# --- VAULT SERVER STARTUP & INITIALIZATION ---
# (This entire section is correct and unchanged)
if [[ -z $VAULT_USERNAME || -z $VAULT_PASSWORD ]]; then
    echo "VAULT_USERNAME and VAULT_PASSWORD are not set"
    exit 1
fi
vault server -config=/vault/config/vault.json &
export VAULT_ADDR="http://127.0.0.1:8200"
echo "Waiting for Vault to start..."
while ! curl -s "$VAULT_ADDR/v1/sys/seal-status" > /dev/null; do
    echo "Waiting for Vault API to be responsive..."
    sleep 2
done
echo "Vault is up and running."
response=$(curl -s "$VAULT_ADDR/v1/sys/seal-status")
initialized=$(echo "$response" | jq -r '.initialized')
sealed=$(echo "$response" | jq -r '.sealed')
echo "Vault Status - Initialized: $initialized, Sealed: $sealed"
if [ "$initialized" = false ]; then
    echo "Initializing Vault..."
    vault operator init > /vault/file/generated_keys.txt
fi
if [ "$sealed" = true ]; then
    echo "Unsealing Vault..."
    grep "Unseal Key" /vault/file/generated_keys.txt | awk '{print $4}' | while read -r key; do
        vault operator unseal "$key"
    done
fi

# --- SETUP USING ROOT TOKEN ---
export VAULT_TOKEN=$(grep "Initial Root Token: " /vault/file/generated_keys.txt | awk '{print $4}')
echo "Configuring Vault policies and auth methods..."
vault secrets enable -path=kv -version=2 kv || echo "KV engine already enabled."
vault auth enable userpass || echo "Userpass auth already enabled."
vault policy write admin-policy /app/admin-policy.hcl
vault write auth/userpass/users/"$VAULT_USERNAME" password="$VAULT_PASSWORD" policies=admin-policy || echo "User $VAULT_USERNAME already exists."
echo "Vault setup complete. Handing over to Python sync service."


# --- THE FIX ---
# Unset the root token from the environment before starting the Python script.
# This ensures the Python script creates its own less-privileged user token
# and does not inherit the root token.
echo "Unsetting root token from environment..."
unset VAULT_TOKEN


# --- START THE PYTHON SYNC SERVICE ---
python3 /app/two_way_sync.py