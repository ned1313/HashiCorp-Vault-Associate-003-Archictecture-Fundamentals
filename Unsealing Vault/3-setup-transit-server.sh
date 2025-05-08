#!/bin/bash
# filepath: c:\gh\HashiCorp-Vault-Associate-003-Archictecture-Fundamentals\Unsealing Vault\3-setup-transit-server.sh

# Create a vault-network in Docker
docker network create vault-network

# Run transit server
docker run -d \
  --name vault-transit \
  --cap-add=IPC_LOCK \
  -p 8210:8200 \
  -v "$(pwd)/config/:/vault/config" \
  -v "$(pwd)/data/:/vault/data" \
  -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_SKIP_VERIFY=true \
  --network vault-network \
  hashicorp/vault:1.17 server

export VAULT_ADDR="http://127.0.0.1:8210"

# Wait for the Vault Transit server to start
echo "Waiting for Vault Transit server to start..."
sleep 5

# Initialize Vault Transit server
echo "Initializing Vault Transit server..."
docker exec -it vault-transit vault operator init -key-shares=1 -key-threshold=1 \
  -format=json > vault-transit-init.json

# Get the root token from the initialization output
export VAULT_TOKEN=$(cat vault-transit-init.json | jq -r '.root_token')

# Get the unseal key from the initialization output
UNSEAL_KEY=$(cat vault-transit-init.json | jq -r '.unseal_keys_b64[0]')

# Unseal the Vault Transit server
echo "Unsealing Vault Transit server..."
vault operator unseal $UNSEAL_KEY

# Remove the json file
rm vault-transit-init.json

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

vault policy write transit-policy transit-policy.hcl
rm transit-policy.hcl
UNSEAL_TOKEN=$(vault token create -orphan -policy="transit-policy" -period=24h -format=json | jq -r '.auth.client_token')

# Show the unseal token
echo "Unseal token for primary server: $UNSEAL_TOKEN"