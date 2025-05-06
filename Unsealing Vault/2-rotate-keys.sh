# Set the Vault address
export VAULT_ADDR="http://127.0.0.1:8200"

# Unseal the Vault server using the unseal keys if you haven't already
vault operator unseal

# Set your Vault token to the root token
export VAULT_TOKEN="ROOT_TOKEN"

# Get the current encryption key
vault operator key-status

# Rotate the encryption keys
vault operator rotate

# Begin the rekeying process
vault operator rekey -init -key-shares=4 -key-threshold=3

# Supply the unseal keys to the rekeying process
vault operator rekey