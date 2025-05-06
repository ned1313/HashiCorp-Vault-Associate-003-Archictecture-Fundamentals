# Get the status of the Vault Primary server
vault status -address=https://localhost:8210 -tls-skip-verify

# Restart the Vault Primary server
Write-Host "Restarting Vault Primary server..."
docker restart vault-primary

# Check the status of the Vault Primary server again
vault status -address=https://localhost:8210 -tls-skip-verify

# Stop the containers and remove the network
docker container rm vault-primary -f
docker container rm vault-transit -f
docker network rm vault-network

# Clean up generated files
Remove-Item -Path "config\*" -Recurse -Force
Remove-Item -Path "certs\*" -Recurse -Force
Remove-Item -Path "vault-transit-init.json" -Force
Remove-Item -Path "vault-primary-init.json" -Force
Remove-Item -Path "vault-primary-data" -Recurse -Force
Remove-Item -Path "vault-transit-data" -Recurse -Force
Remove-Item -Path "config" -Recurse -Force
Remove-Item -Path "certs" -Recurse -Force