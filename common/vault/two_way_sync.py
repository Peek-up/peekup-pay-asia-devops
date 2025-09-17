import os
import time
import logging
import hashlib
import json
import hvac
from dotenv import dotenv_values

# --- Configuration ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200")
VAULT_USERNAME = os.environ.get("VAULT_USERNAME")
VAULT_PASSWORD = os.environ.get("VAULT_PASSWORD")
ENV_FILE = "/config/.env"
VAULT_KV_PATH = "env"
POLL_INTERVAL = 15

# --- Core Functions (Unchanged except for removing global flags) ---

def get_vault_client():
    """Initializes and EXPLICITLY authenticates the HVAC client."""
    client = hvac.Client(url=VAULT_ADDR)
    try:
        login_response = client.auth.userpass.login(
            username=VAULT_USERNAME,
            password=VAULT_PASSWORD,
        )
        client.token = login_response['auth']['client_token']
        logging.info("Successfully authenticated with Vault and user token is now active.")
        if client.is_authenticated():
            return client
        else:
            logging.error("Authentication failed despite receiving a token.")
            return None
    except Exception as e:
        logging.error(f"Failed to authenticate with Vault: {e}")
        return None

def get_env_data(filepath):
    if not os.path.exists(filepath):
        return {}
    return dict(sorted(dotenv_values(filepath).items()))

def get_vault_data(client):
    try:
        response = client.secrets.kv.v2.read_secret_version(mount_point='kv', path=VAULT_KV_PATH)
        return dict(sorted(response['data']['data'].items()))
    except hvac.exceptions.InvalidPath:
        return {}
    except Exception as e:
        logging.error(f"Could not read from Vault: {e}")
        return {}

def calculate_hash(data_dict):
    if not data_dict:
        return 'empty'
    encoded_str = json.dumps(data_dict, sort_keys=True).encode('utf-8')
    return hashlib.md5(encoded_str).hexdigest()

def sync_to_vault(client, data):
    if not data:
        logging.info("No data to sync to Vault.")
        return
    try:
        client.secrets.kv.v2.create_or_update_secret(mount_point='kv', path=VAULT_KV_PATH, secret=data)
        logging.info("Successfully synced .env changes to Vault.")
    except Exception as e:
        logging.error(f"Failed to write to Vault: {e}")

def sync_to_env(data, filepath):
    logging.info("Updating local .env file with changes from Vault.")
    try:
        with open(filepath, 'w') as f:
            for key, value in data.items():
                f.write(f"{key}='{value}'\n")
    except Exception as e:
        logging.error(f"Failed to write to .env file: {e}")

# --- Main Application Logic (Completely rewritten for polling) ---

def main():
    client = get_vault_client()
    if not client:
        logging.error("Could not get authenticated Vault client. Exiting.")
        return

    # --- Initial State ---
    logging.info("Establishing initial sync baseline...")
    # On the very first run, we establish that the .env file is the source of truth.
    initial_env_data = get_env_data(ENV_FILE)
    if initial_env_data:
        logging.info("Performing initial sync from .env to Vault.")
        sync_to_vault(client, initial_env_data)
    else:
        logging.warning("Initial .env file is empty or not found. Skipping initial sync.")
    
    # Store the hashes of the current state after our initial sync.
    last_env_hash = calculate_hash(initial_env_data)
    last_vault_hash = calculate_hash(get_vault_data(client))
    logging.info("Initial sync complete. Starting polling loop.")

    # --- Main Polling Loop ---
    try:
        while True:
            time.sleep(POLL_INTERVAL)

            # In each loop, get the current state of both sources
            current_env_hash = calculate_hash(get_env_data(ENV_FILE))
            current_vault_hash = calculate_hash(get_vault_data(client))

            # Determine what has changed since the last check
            env_changed = (current_env_hash != last_env_hash)
            vault_changed = (current_vault_hash != last_vault_hash)

            if env_changed and not vault_changed:
                # SCENARIO: .env file was modified. Sync from .env -> Vault.
                logging.info("Change detected in local .env file. Syncing to Vault...")
                sync_to_vault(client, get_env_data(ENV_FILE))
                # Update our "last known" hashes to the new state
                last_env_hash = current_env_hash
                last_vault_hash = calculate_hash(get_vault_data(client))

            elif vault_changed and not env_changed:
                # SCENARIO: Vault was modified. Sync from Vault -> .env.
                logging.info("Change detected in Vault. Syncing to local .env file...")
                sync_to_env(get_vault_data(client), ENV_FILE)
                # Update our "last known" hashes to the new state
                last_vault_hash = current_vault_hash
                last_env_hash = calculate_hash(get_env_data(ENV_FILE))
            
            elif env_changed and vault_changed:
                # SCENARIO: CONFLICT! Both were modified. Vault wins.
                logging.warning("CONFLICT DETECTED! Both .env and Vault changed. Overwriting local file with Vault data as per policy.")
                sync_to_env(get_vault_data(client), ENV_FILE)
                # Update our "last known" hashes to the new state from Vault
                last_vault_hash = current_vault_hash
                last_env_hash = calculate_hash(get_env_data(ENV_FILE))

    except KeyboardInterrupt:
        logging.info("Shutting down sync service.")
    except Exception as e:
        logging.error(f"An unexpected error occurred in the main loop: {e}")

if __name__ == "__main__":
    main()