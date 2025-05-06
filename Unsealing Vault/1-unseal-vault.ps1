# Set the Vault address
$env:VAULT_ADDR = "http://127.0.0.1:8200"

# Run the unseal command with the first unseal key
vault operator unseal

# Use the UI to unseal the vault
# Open a web browser and navigate to the Vault UI at http://127.0.1:8200/ui

# Check vault status
vault status

# Set the VAULT_TOKEN environment variable to the root token
$env:VAULT_TOKEN = "ROOT_TOKEN"

# Seal the vault using the API with curl
curl -X POST http://127.0.1:8200/v1/sys/seal -H "X-Vault-Token: $env:VAULT_TOKEN"