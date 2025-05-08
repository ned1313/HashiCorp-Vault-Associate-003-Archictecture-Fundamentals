# Create a vault-network in Docker
docker network create vault-network

# Run transit server
docker run -d `
  --name vault-transit `
  --cap-add=IPC_LOCK `
  -p 8210:8200 `
  -v "$(Get-Location)\config\:/vault/config" `
  -v "$(Get-Location)\data\:/vault/data" `
  -e VAULT_ADDR=http://127.0.0.1:8200 `
  -e VAULT_SKIP_VERIFY=true `
  --network vault-network `
  hashicorp/vault:1.17 server

$env:VAULT_ADDR = "http://127.0.0.1:8210"

# Wait for the Vault Transit server to start
Write-Host "Waiting for Vault Transit server to start..."
Start-Sleep -Seconds 5

# Initialize Vault Transit server
Write-Host "Initializing Vault Transit server..."
docker exec -it vault-transit vault operator init -key-shares=1 -key-threshold=1 `
  -format=json | Out-File -FilePath "vault-transit-init.json" -Encoding ASCII

# Get the root token from the initialization output
$env:VAULT_TOKEN = (Get-Content -Path "vault-transit-init.json" | ConvertFrom-Json).root_token

# Get the unseal key from the initialization output
$unsealKey = (Get-Content -Path "vault-transit-init.json" | ConvertFrom-Json).unseal_keys_b64[0]

# Unseal the Vault Transit server
Write-Host "Unsealing Vault Transit server..."
vault operator unseal $unsealKey

# Remove the json file
Remove-Item vault-transit-init.json -Force

# Set up the Transit engine and create a key for the primary server
Write-Host "Setting up Transit engine and creating key for primary server..."
vault secrets enable transit
vault write -f transit/keys/autounseal

# Add policy for the primary server to access the Transit engine
@"
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
"@ | Out-File -FilePath "transit-policy.hcl" -Encoding ASCII

vault policy write transit-policy transit-policy.hcl
Remove-Item transit-policy.hcl -Force
$UNSEAL_TOKEN = $(vault token create -orphan -policy="transit-policy" -period=24h -field=token)

# Show the unseal token
Write-Host "Unseal token for primary server: $UNSEAL_TOKEN"

