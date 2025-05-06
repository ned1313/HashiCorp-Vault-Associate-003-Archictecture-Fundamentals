#!/usr/bin/env pwsh
# PowerShell script to set up two Vault servers with TLS certificates

# Create necessary directories
New-Item -Path "config\vault-transit" -ItemType Directory -Force
New-Item -Path "config\vault-primary" -ItemType Directory -Force
New-Item -Path "certs" -ItemType Directory -Force

# Generate TLS certificates for both Vault servers
Write-Host "Generating TLS certificates for Vault servers..."

# Create root CA
openssl genrsa -out certs/ca.key 2048
openssl req -new -x509 -days 365 -key certs/ca.key -out certs/ca.crt -subj "/CN=VaultCA"

# Function to generate certificates for a Vault server
function Create-VaultCert {
    param (
        [string]$serverName
    )
    
    # Create private key
    openssl genrsa -out "certs/$serverName.key" 2048
    
    # Create CSR (Certificate Signing Request)
    openssl req -new -key "certs/$serverName.key" -out "certs/$serverName.csr" `
        -subj "/CN=$serverName" `
        -addext "subjectAltName = DNS:$serverName, DNS:localhost, IP:127.0.0.1"
    
    # Create a config file for SANs
    @"
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $serverName
DNS.2 = localhost
IP.1 = 127.0.0.1
"@ | Out-File -FilePath "certs/$serverName.ext" -Encoding ASCII
    
    # Sign the CSR with our CA
    openssl x509 -req -in "certs/$serverName.csr" -CA certs/ca.crt -CAkey certs/ca.key `
        -CAcreateserial -out "certs/$serverName.crt" -days 365 `
        -extfile "certs/$serverName.ext"
    
    # Create config directory if it doesn't exist
    New-Item -Path "config\$serverName" -ItemType Directory -Force
    
    # Copy certificates to config directory
    Copy-Item "certs/$serverName.key" -Destination "config/$serverName/tls.key"
    Copy-Item "certs/$serverName.crt" -Destination "config/$serverName/tls.crt"
    Copy-Item "certs/ca.crt" -Destination "config/$serverName/ca.crt"
    
    # Create Vault config file
    @"
ui = true
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/config/tls.crt"
  tls_key_file  = "/vault/config/tls.key"
  tls_client_ca_file = "/vault/config/ca.crt"
}

api_addr = "https://$serverName`:8200"
disable_mlock = true
"@ | Out-File -FilePath "config/$serverName/vault.hcl" -Encoding ASCII
    
    Write-Host "Configuration and certificates for $serverName created successfully"
}

# Generate certificates for both servers
Create-VaultCert -serverName "vault-transit"
Create-VaultCert -serverName "vault-primary"

# Create Docker network for Vault servers
Write-Host "Creating Docker network for Vault servers..."
docker network create vault-network

# Run Vault Transit server
Write-Host "Starting Vault Transit server..."
docker run -d `
  --name vault-transit `
  --cap-add=IPC_LOCK `
  -p 8200:8200 `
  -v "$(Get-Location)\config\vault-transit:/vault/config" `
  -v "$(Get-Location)\vault-transit-data:/vault/data" `
  -e VAULT_ADDR=https://127.0.0.1:8200 `
  -e VAULT_SKIP_VERIFY=true `
  --network vault-network `
  hashicorp/vault:1.17 server

$env:VAULT_ADDR = "https://localhost:8200"
$env:VAULT_SKIP_VERIFY = "true"

# Pause to allow Vault Transit server to start
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

# Add the autounseal configuration to the primary server's config file
@"
seal "transit" {
  address = "https://vault-transit:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  tls_skip_verify = "true"
}
"@ | Out-File -FilePath "config/vault-primary/vault.hcl" -Append -Encoding ASCII


# Run Vault Primary server
Write-Host "Starting Vault Primary server..."
docker run -d `
  --name vault-primary `
  --cap-add=IPC_LOCK `
  -p 8210:8200 `
  -v "$(Get-Location)\config\vault-primary\:/vault/config" `
  -v "$(Get-Location)\vault-primary-data\:/vault/data" `
  -e VAULT_ADDR=https://127.0.0.1:8200 `
  -e VAULT_SKIP_VERIFY=true `
  -e VAULT_TOKEN=$UNSEAL_TOKEN `
  --network vault-network `
  hashicorp/vault:1.17 server

# Pause to allow Vault Primary server to start
Start-Sleep -Seconds 5

# Initialize Vault Primary server
Write-Host "Initializing Vault Primary server..."
docker exec -it vault-primary vault operator init -recovery-shares=1 -recovery-threshold=1 `
  -format=json | Out-File -FilePath "vault-primary-init.json" -Encoding ASCII

# Get the root token from the initialization output
$PrimaryRootToken = (Get-Content -Path "vault-primary-init.json" | ConvertFrom-Json).root_token

# Print out the Vault server addresses and tokens
Write-Host "Vault Transit server address: https://localhost:8200"
Write-Host "Vault Transit server unseal key: $unsealKey"
Write-Host "Vault Transit server root token: $env:VAULT_TOKEN"
Write-Host "Vault Primary server address: https://localhost:8210"
Write-Host "Vault Primary server root token: $PrimaryRootToken"  
