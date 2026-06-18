# Deploy Wazuh Docker in single node configuration

This deployment is defined in the `docker-compose.yml` file with one Wazuh manager containers, one Wazuh indexer containers, and one Wazuh dashboard container. It can be deployed by following these steps: 

1) Increase max_map_count on your host (Linux). This command must be run with root permissions:
```
sudo sysctl -w vm.max_map_count=262144
```
```
sudo docker node update --label-add wazuh-data=true $(hostname)
```
2) Run the certificate creation script:
```
docker compose -f generate-indexer-certs.yml run --rm generator
```
3) Set Script Permissions - Make your custom entrypoint script executable to prevent the permission denied container crashes.
```
cd /scripts
```
```
sudo chmod +x wazuh-env.sh
```
4) Create Swarm Secrets (Bootstrap Authentication) Because we are using the default hashed configuration, generate the required SecretPassword secrets so the internal services (Filebeat & OpenSearch) can communicate successfully. (Note: We will change this password through the Wazuh UI later).
```
mkdir -p .secrets
```
```
echo "admin" > .secrets/idx_user
```
```
echo "SecretPassword" > .secrets/idx_pass
```
```
echo "wazuh-wui" > .secrets/api_user
```
```
echo "MyS3cr37P450r.*-" > .secrets/api_pass
```
```
echo "kibanaserver" > .secrets/dash_user
```
```
echo "kibanaserver" > .secrets/dash_pass
```
```
sudo chmod 600 .secrets/*
```
5) Deploy the Stack - Ensure your SSL certificates are properly situated in ./config/wazuh_indexer_ssl_certs/, then launch the cluster.
```
sudo docker stack deploy -c docker-compose.yml wazuh
```
6) Monitor the Boot Sequence - Wazuh boots sequentially. Tail the database logs and wait for it to authorize. Wait until you see: Cluster health status changed from [RED] to [GREEN]. Press CTRL+C to exit the logs.
```
sudo docker service logs wazuh_wazuh-indexer -f
```
7) Verify and Access - Check the global cluster status to ensure the manager and dashboard have successfully attached to the database and booted.
```
sudo docker service ls | grep wazuh
```
Once all three services firmly report 1/1, Traefik will instantly route your domain.

Navigate to: https://wazuh.app.dsolutiontech.net

Username: admin

Password: SecretPassword

The environment takes about 1 minute to get up (depending on your Docker host) for the first time since Wazuh Indexer must be started for the first time and the indexes and index patterns must be generated. Remember to change`wazuh.app.dsolutiontech.net` to you domain
