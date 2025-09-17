#!/usr/bin/env bash
set -e

pushd /epic

export VAULT_ADDR="http://127.0.0.1:8200"
vault login -method=userpass username=$VAULT_USERNAME password=$VAULT_PASSWORD
export VAULT_TOKEN=$(vault print token)

# Function to update Vault from .env
update_vault_from_env() {
    echo "Updating Vault from .env file..."
    
    local args=()
    local key=""
    local value=""
    local in_multiline=false

    # Read the .env file line by line, handling multi-line values in single quotes
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines if not inside a multi-line value
        if ! $in_multiline; then
            [[ "$line" =~ ^\s*# ]] && continue
            [[ -z "$line" ]] && continue
        fi
        
        if ! $in_multiline; then
            # Start of a new variable
            key=$(echo "$line" | cut -d'=' -f1)
            val_part=$(echo "$line" | cut -d'=' -f2-)
            
            # Check if value starts with a single quote but does not end with one on the same line
            if [[ "$val_part" =~ ^\' && ! "$val_part" =~ \'$ ]]; then
                in_multiline=true
                value="${val_part:1}" # Store value, removing the starting quote
            else
                # This is a single-line value
                value=$(echo "$val_part" | sed -e "s/^'//" -e "s/'$//") # Remove quotes
                args+=("$key=$value")
            fi
        else
            # We are inside a multi-line value
            if [[ "$line" =~ \'$ ]]; then
                # This is the last line of the multi-line value
                in_multiline=false
                value+=$'\n'
                value+=$(echo "$line" | sed "s/'$//") # Append line, removing the ending quote
                args+=("$key=$value")
                key=""
                value=""
            else
                # This is a middle line of the multi-line value
                value+=$'\n'
                value+="$line"
            fi
        fi
    done < /epic/.env
    
    # Update Vault using the parsed arguments
    if [ ${#args[@]} -gt 0 ]; then
        vault kv put kv/env "${args[@]}"
        echo "Vault updated with .env content"
    fi
}

# Always update Vault from .env on startup
echo "Always updating Vault from .env file on startup..."
update_vault_from_env

# Create backup
cp /epic/.env /epic/.env.back
echo "Initial sync completed"

# Start the two-way sync in the background
/epic/two-way-sync.sh &

# Start consul-template (optional, if you still need it for other templates)
consul-template \
    -vault-default-lease-duration=10s \
    -vault-renew-token=false \
    -template "env.tpl:env.tmp:bash -c 'echo \"consul-template is running but two-way sync handles env updates\"'" &

# Wait for any process to exit
wait -n

# Exit with status of process that exited first
exit $?