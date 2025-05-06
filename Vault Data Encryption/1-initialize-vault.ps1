# Run basic server
docker run -d `
  --name vault-basic `
  --cap-add=IPC_LOCK `
  -p 8200:8200 `
  -v "$(Get-Location)\config\:/vault/config" `
  -v "$(Get-Location)\data\:/vault/data" `
  -e VAULT_ADDR=http://127.0.0.1:8200 `
  -e VAULT_SKIP_VERIFY=true `
  hashicorp/vault:1.17 server

$env:VAULT_ADDR = "http://127.0.0.1:8200"

# Check Vault status
vault status

# Initialize Vault
vault operator init -key-shares=3 -key-threshold=2