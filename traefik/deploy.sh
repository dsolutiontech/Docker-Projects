#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "======================================================="
echo "   Traefik Production Swarm Deployment Wizard"
echo "======================================================="
echo ""

# Capture the actual user running the script (even if executed via sudo)
CURRENT_USER=${SUDO_USER:-$USER}
echo "--> Detected user: $CURRENT_USER"

# 1. Docker Installation
echo "--> Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing the latest official Docker engine (this may take a minute)..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    # Suppress standard output to prevent the massive systemd text dump
    sudo sh get-docker.sh > /dev/null
    rm get-docker.sh
    
    # Add the current user to the docker group so they can run commands without sudo
    sudo usermod -aG docker "$CURRENT_USER"
    echo "Docker installed successfully."
else
    echo "Docker is already installed."
fi

# 2. Docker Swarm Initialization
echo ""
echo "--> Checking Docker Swarm status..."
# We use sudo here just in case the user hasn't logged out/in yet to apply docker group permissions.
if ! sudo docker info | grep -q "Swarm: active"; then
    echo "Initializing Docker Swarm..."
    # Try default init. If it fails due to multiple IPs, catch the error and prompt the user.
    if ! sudo docker swarm init > /dev/null 2>&1; then
        echo ""
        echo "⚠️ Multiple network interfaces detected."
        echo "Docker Swarm needs to know which IP address to use for cluster communication."
        echo "Here are your current IP addresses:"
        # List all IPs, stripping extra spaces and blank lines
        hostname -I | tr ' ' '\n' | grep -v '^$'
        echo ""
        read -p "Enter the IP address you want to advertise for the Swarm: " ADVERTISE_IP
        sudo docker swarm init --advertise-addr "$ADVERTISE_IP"
    fi
    echo "Swarm initialized. This node is now the Swarm Manager."
else
    echo "Docker Swarm is already active on this node."
fi

# 3. Directory Structure & Strict Permissions
echo ""
echo "--> Setting up directories and permissions..."
sudo mkdir -p /opt/proxy/traefik-dynamic
# Lock down the root proxy folder to root for security
sudo chown root:root /opt/proxy
# Give the current user complete ownership of the dynamic routing folder
sudo chown -R "$CURRENT_USER":"$CURRENT_USER" /opt/proxy/traefik-dynamic

# 4. Copy Configuration Files
echo "--> Copying configuration files..."
if [ -f "docker-compose.yml" ]; then
    sudo cp docker-compose.yml /opt/proxy/docker-compose.yml
else
    echo "❌ Error: docker-compose.yml not found in the current directory."
    exit 1
fi

if [ -f "middlewares.yml" ]; then
    sudo cp middlewares.yml /opt/proxy/traefik-dynamic/middlewares.yml
    # Ensure proper ownership of the copied file
    sudo chown "$CURRENT_USER":"$CURRENT_USER" /opt/proxy/traefik-dynamic/middlewares.yml
    echo "middlewares.yml copied successfully."
else
    echo "⚠️ Warning: middlewares.yml not found. Global security headers will not be applied."
fi

# 5. Sanitize Configuration Files (Self-Healing)
echo "--> Sanitizing files to remove Windows line endings and hidden tabs..."
sudo sed -i 's/\r$//' /opt/proxy/docker-compose.yml
if [ -f "/opt/proxy/traefik-dynamic/middlewares.yml" ]; then
    # Strip Windows CRLF
    sudo sed -i 's/\r$//' /opt/proxy/traefik-dynamic/middlewares.yml
    # Replace invalid YAML Tabs with two spaces
    sudo sed -i 's/\t/  /g' /opt/proxy/traefik-dynamic/middlewares.yml
fi

# 6. Install Dependencies
echo "--> Checking and installing htpasswd utility..."
# Silencing the apt output to keep the console wizard clean
sudo apt-get update > /dev/null && sudo apt-get install apache2-utils -y > /dev/null

# 7. Docker Network Configuration
echo "--> Checking Docker overlay network..."
if ! sudo docker network ls | grep -q "frontend"; then
    echo "Creating overlay network 'frontend'..."
    sudo docker network create --driver=overlay frontend
else
    echo "Network 'frontend' already exists."
fi

# 8. Traefik Dashboard Authentication Secret
echo ""
echo "--> Configuring Traefik Dashboard Security"
if sudo docker secret ls | grep -q "traefik_dashboard_auth"; then
    echo "Secret 'traefik_dashboard_auth' already exists. Skipping..."
else
    read -p "Enter a username for the Traefik Dashboard: " DASH_USER
    read -s -p "Enter a password for the Traefik Dashboard: " DASH_PASS
    echo ""
    
    # Generate htpasswd hash securely in memory
    AUTH_HASH=$(htpasswd -nB -b "$DASH_USER" "$DASH_PASS")
    
    # Inject directly into Docker Swarm
    printf "%s" "$AUTH_HASH" | sudo docker secret create traefik_dashboard_auth -
    echo "Traefik dashboard credentials securely stored in Swarm."
fi

# 9. Cloudflare API Token Secret
echo ""
echo "--> Configuring Cloudflare API Token"
if sudo docker secret ls | grep -q "traefik_cf_api_token"; then
    echo "Secret 'traefik_cf_api_token' already exists. Skipping..."
else
    read -s -p "Enter your Cloudflare API Token: " CF_TOKEN
    echo ""
    
    # Inject directly into Docker Swarm without newlines
    printf "%s" "$CF_TOKEN" | sudo docker secret create traefik_cf_api_token -
    echo "Cloudflare token securely stored in Swarm."
fi

# 10. Environment Variables
echo ""
echo "--> Configuring Environment Variables"

BASE_DOMAIN=""
while [ -z "$BASE_DOMAIN" ]; do
    read -p "Enter the Base Domain (Required, e.g., app.dsolutiontech.net): " BASE_DOMAIN
    if [ -z "$BASE_DOMAIN" ]; then
        echo "❌ Error: Base Domain cannot be empty. Please try again."
    fi
done

LE_EMAIL=""
while [ -z "$LE_EMAIL" ]; do
    read -p "Enter the Let's Encrypt Email (Required, e.g., admin@dsolutiontech.net): " LE_EMAIL
    if [ -z "$LE_EMAIL" ]; then
        echo "❌ Error: Let's Encrypt Email cannot be empty. Please try again."
    fi
done

export BASE_DOMAIN
export LE_EMAIL

# 11. Deploy to Swarm
echo ""
echo "--> Deploying Proxy Stack to the Swarm..."
# Pass variables directly inline with sudo to bypass environment stripping
sudo BASE_DOMAIN="$BASE_DOMAIN" LE_EMAIL="$LE_EMAIL" docker stack deploy -c /opt/proxy/docker-compose.yml proxy

echo ""
echo "Deployment triggered successfully! Traefik is provisioning."
echo "You can monitor the deployment using: sudo docker service ls"
