#!/bin/bash
# Bash script to set up two Vault servers with TLS certificates

# Exit on any error
set -e

# Print commands before execution (helpful for debugging)
set -x

echo "Setting up Vault servers with TLS certificates..."

# Create necessary directories
mkdir -p config/vault-transit config/vault-primary certs

# Generate TLS certificates for both Vault servers
echo "Generating TLS certificates for Vault servers..."

# Create root CA
openssl genrsa -out certs/ca.key 2048
openssl req -new -x509 -days 365 -key certs/ca.key -out certs/ca.crt -subj "/CN=VaultCA"

# Function to generate certificates for a Vault server
create_vault_cert() {
    local server_name=$1
    
    echo "Creating certificates for $server_name..."
    
    # Create private key
    openssl genrsa -out "certs/$server_name.key" 2048
    
    # Create CSR (Certificate Signing Request)
    openssl req -new -key "certs/$server_name.key" -out "certs/$server_name.csr" \
        -subj "/CN=$server_name" \
        -addext "subjectAltName = DNS:$server_name, DNS:localhost, IP:127.0.0.1"
    
    # Create a config file for SANs
    cat > "certs/$server_name.ext" << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $server_name
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Sign the CSR with our CA
    openssl x509 -req -in "certs/$server_name.csr" -CA certs/ca.crt -CAkey certs/ca.key \
        -CAcreateserial -out "certs/$server_name.crt" -days 365 \
        -extfile "certs/$server_name.ext"
    
    # Create config directory if it doesn't exist
    mkdir -p "config/$server_name"
    
    # Copy certificates to config directory
    cp "certs/$server_name.key" "config/$server_name/tls.key"
    cp "certs/$server_name.crt" "config/$server_name/tls.crt"
    cp "certs/ca.crt" "config/$server_name/ca.crt"
    
    # Create Vault config file
    cat > "config/$server_name/vault.hcl" << EOF
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

api_addr = "https://$server_name:8200"
disable_mlock = true
EOF
    
    echo "Configuration and certificates for $server_name created successfully"
}

# Generate certificates for both servers
create_vault_cert "vault-transit"
create_vault_cert "vault-primary"

# Create Docker network for Vault servers
echo "Creating Docker network for Vault servers..."
docker network create vault-network || echo "Network already exists"

# Create data directories with proper permissions
mkdir -p vault-transit-data vault-primary-data
chmod 777 vault-transit-data vault-primary-data


# Run Vault Transit server
echo "Starting Vault Transit server..."
docker run -d \
  --name vault-transit \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -v "$(pwd)/config/vault-transit:/vault/config" \
  -v "$(pwd)/vault-transit-data:/vault/data" \
  -e VAULT_ADDR=https://127.0.0.1:8200 \
  -e VAULT_SKIP_VERIFY=true \
  --network vault-network \
  hashicorp/vault:1.17 server

export VAULT_ADDR="https://localhost:8200"
export VAULT_SKIP_VERIFY="true"

# Pause to allow Vault Transit server to start
echo "Waiting for Vault Transit server to start..."
sleep 5

# Initialize Vault Transit server
echo "Initializing Vault Transit server..."
docker exec vault-transit vault operator init -key-shares=1 -key-threshold=1 \
  -format=json > vault-transit-init.json

# Get the root token from the initialization output
export VAULT_TOKEN=$(jq -r .root_token vault-transit-init.json)

# Get the unseal key from the initialization output
UNSEAL_KEY=$(jq -r .unseal_keys_b64[0] vault-transit-init.json)

# Unseal the Vault Transit server
echo "Unsealing Vault Transit server..."
vault operator unseal $UNSEAL_KEY

# Set up the Transit engine and create a key for the primary server
echo "Setting up Transit engine and creating key for primary server..."
vault secrets enable transit
vault write -f transit/keys/autounseal

# Add policy for the primary server to access the Transit engine
cat > transit-policy.hcl << EOF
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
EOF

vault policy write transit-policy - < transit-policy.hcl
rm transit-policy.hcl

UNSEAL_TOKEN=$(vault token create -orphan -policy="transit-policy" -period=24h -field=token)

# Add the autounseal configuration to the primary server's config file
cat >> "config/vault-primary/vault.hcl" << EOF
seal "transit" {
  address = "https://vault-transit:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  tls_skip_verify = "true"
}
EOF

# Run Vault Primary server
echo "Starting Vault Primary server..."
docker run -d \
  --name vault-primary \
  --cap-add=IPC_LOCK \
  -p 8210:8200 \
  -v "$(pwd)/config/vault-primary:/vault/config" \
  -v "$(pwd)/vault-primary-data:/vault/data" \
  -e VAULT_ADDR=https://127.0.0.1:8200 \
  -e VAULT_SKIP_VERIFY=true \
  -e VAULT_TOKEN=$UNSEAL_TOKEN \
  --network vault-network \
  hashicorp/vault:1.17 server

# Pause to allow Vault Primary server to start
echo "Waiting for Vault Primary server to start..."
sleep 5

# Initialize Vault Primary server
echo "Initializing Vault Primary server..."
docker exec vault-primary vault operator init -recovery-shares=1 -recovery-threshold=1 \
  -format=json > vault-primary-init.json

# Get the root token from the initialization output
PRIMARY_ROOT_TOKEN=$(jq -r .root_token vault-primary-init.json)

# Print out the Vault server addresses and tokens
echo "====== VAULT SETUP COMPLETE ======"
echo "Vault Transit server address: https://localhost:8200"
echo "Vault Transit server unseal key: $UNSEAL_KEY"
echo "Vault Transit server root token: $VAULT_TOKEN"
echo "Vault Primary server address: https://localhost:8210"
echo "Vault Primary server root token: $PRIMARY_ROOT_TOKEN"
echo "=================================="