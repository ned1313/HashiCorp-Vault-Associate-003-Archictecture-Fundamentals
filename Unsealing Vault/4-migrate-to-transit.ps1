# Stop the vault-basic container if it's running
docker container stop vault-basic

# Attach to the vault-network
docker network connect vault-network vault-basic

# Add a config file for the basic server to use the Transit server as the unseal key provider
@"
seal "transit" {
  address = "http://localhost:8210"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  token = "$UNSEAL_TOKEN"
}
"@ | Out-File -FilePath "../Vault Data Encryption/config/seal-config.hcl" -Encoding ASCII

# Start the basic server with the added config file
docker container start vault-basic

# Update VAULT_ADDR to point to the basic server
$env:VAULT_ADDR = "http://localhost:8200"

# Begin the unsealing process with migration to the Transit server
vault operator unseal -migrate

# Restart the vault-basic container to verify autounseal
docker container restart vault-basic

# Check vault status to verify that the server is unsealed
vault status

# Clean up the environment by removing the containers and network
docker container rm -f vault-basic vault-transit
docker network rm vault-network

# Delete the data directory and seal-config file
Remove-Item -Path "..\Vault Data Encryption\config\seal-config.hcl" -Force
Remove-Item -Path "$(Get-Location)\data" -Force


