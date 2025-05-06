# Get the status of the Vault Primary server
vault status -address=https://localhost:8210 -tls-skip-verify

# Restart the Vault Primary server
docker restart vault-primary

# Check the status of the Vault Primary server again
vault status -address=https://localhost:8210 -tls-skip-verify

# Stop the containers and remove the network
docker container rm vault-primary -f
docker container rm vault-transit -f
docker network rm vault-network

# Clean up generated files
sudo rm -rf config/*
sudo rm -rf certs/*
sudo rm -f vault-transit-init.json
sudo rm -f vault-primary-init.json
sudo rm -rf vault-primary-data
sudo rm -rf vault-transit-data
sudo rm -rf config
sudo rm -rf certs