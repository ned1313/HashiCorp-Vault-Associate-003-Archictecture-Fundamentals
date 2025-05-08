# Stop the vault-basic container if it's running
docker container stop vault-basic

# Attach to the vault-network
docker network connect vault-network vault-basic

# Fix permissions for config directory
sudo chmod 777 -R ../Vault\ Data\ Encryption/config

# Set the UNSEAL_TOKEN value, replace TOKEN_VALUE with the actual token
UNSEAL_TOKEN=TOKEN_VALUE

# Add a config file for the basic server to use the Transit server as the unseal key provider
cat > "../Vault Data Encryption/config/seal-config.hcl" << EOF
seal "transit" {
  address = "http://vault-transit:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  token = "$UNSEAL_TOKEN"
}
EOF

# Start the basic server with the added config file
docker container start vault-basic

# Update VAULT_ADDR to point to the basic server
export VAULT_ADDR="http://localhost:8200"

# Check the status of the basic server
vault status

# Begin the unsealing process with migration to the Transit server
vault operator unseal -migrate

# Restart the vault-basic container to verify autounseal
docker container restart vault-basic

# Check vault status to verify that the server is unsealed
vault status

# Clean up the environment by removing the containers and network
docker container rm -f vault-basic vault-transit
docker network rm vault-network

# Delete the data directory and seal-config file (requires sudo)
sudo rm -f "../Vault Data Encryption/config/seal-config.hcl"
sudo rm -rf "$(pwd)/data"
sudo rm -rf "$(pwd)/../Vault Data Encryption/data"