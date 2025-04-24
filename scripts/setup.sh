#!/bin/bash

# setup.sh - Initial setup script for n8n deployment with webhook processors
# This script prepares the VPS environment for running n8n with Docker

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

# Print banner
echo "====================================================="
echo "       n8n Self-Hosted Deployment Setup Script       "
echo "====================================================="
echo ""

# Check for required utilities
for cmd in docker docker-compose curl wget; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is required but not installed."
    echo "Please install $cmd and try again."
    exit 1
  fi
done

# Create necessary directories
echo "Creating directory structure..."
mkdir -p ./volumes/{postgres,redis,n8n,letsencrypt}
mkdir -p ./traefik/dynamic

# Set proper permissions
echo "Setting appropriate permissions..."
chmod -R 755 ./volumes
chmod -R 700 ./volumes/postgres
chmod -R 700 ./volumes/n8n

# Check if .env file exists
if [ ! -f .env ]; then
  echo "Creating .env file from .env.example..."
  if [ -f .env.example ]; then
    cp .env.example .env
    echo "Please edit the .env file with your configuration"
    echo "Run this script again after editing the .env file"
    exit 0
  else
    echo "Error: .env.example file not found!"
    exit 1
  fi
fi

# Load environment variables
set -a
source .env
set +a

# Generate random encryption keys if not set
if [ "$N8N_ENCRYPTION_KEY" = "your_very_secure_encryption_key" ]; then
  NEW_KEY=$(openssl rand -hex 16)
  sed -i "s/your_very_secure_encryption_key/$NEW_KEY/g" .env
  echo "Generated new N8N_ENCRYPTION_KEY"
fi

if [ "$N8N_USER_MANAGEMENT_JWT_SECRET" = "another_very_secure_jwt_secret" ]; then
  NEW_JWT=$(openssl rand -hex 16)
  sed -i "s/another_very_secure_jwt_secret/$NEW_JWT/g" .env
  echo "Generated new N8N_USER_MANAGEMENT_JWT_SECRET"
fi

# Create Traefik configuration files if they don't exist
if [ ! -f ./traefik/config.yml ]; then
  echo "Creating Traefik configuration..."
  cat > ./traefik/config.yml << 'EOL'
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: n8n-network
  file:
    directory: "/etc/traefik/dynamic"
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${SSL_EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO

accessLog: {}
EOL
fi

# Create dashboard.yml for Traefik
if [ ! -f ./traefik/dynamic/dashboard.yml ]; then
  echo "Creating Traefik dashboard configuration..."
  
  # Generate a random password for Traefik dashboard
  TRAEFIK_USER="admin"
  TRAEFIK_PASSWORD=$(openssl rand -hex 8)
  HASHED_PASSWORD=$(openssl passwd -apr1 $TRAEFIK_PASSWORD)
  
  # Replace special characters for sed
  HASHED_PASSWORD=$(echo $HASHED_PASSWORD | sed 's/\//\\\//g')
  
  cat > ./traefik/dynamic/dashboard.yml << EOL
http:
  middlewares:
    traefik-auth:
      basicAuth:
        users:
          - "${TRAEFIK_USER}:${HASHED_PASSWORD}"
EOL

  echo "Traefik dashboard credentials:"
  echo "  Username: $TRAEFIK_USER"
  echo "  Password: $TRAEFIK_PASSWORD"
  echo "  (Please save these credentials in a secure location)"
fi

# Pull the required Docker images
echo "Pulling required Docker images..."
docker pull n8nio/n8n:latest
docker pull postgres:14-alpine
docker pull redis:7-alpine
docker pull traefik:v2.10

# Create backup and restore scripts
echo "Creating backup script..."
cat > ./scripts/backup.sh << 'EOL'
#!/bin/bash
# Backup script for n8n deployment

BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/n8n_backup_${TIMESTAMP}.tar.gz"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Stop n8n services to ensure consistent backup
echo "Stopping n8n services..."
docker compose stop n8n-primary n8n-worker n8n-webhook

# Create backup
echo "Creating backup archive..."
tar -czf "${BACKUP_FILE}" ./volumes/n8n ./volumes/postgres .env

# Restart services
echo "Restarting n8n services..."
docker compose start n8n-primary n8n-worker n8n-webhook

echo "Backup completed: ${BACKUP_FILE}"
EOL

echo "Creating restore script..."
cat > ./scripts/restore.sh << 'EOL'
#!/bin/bash
# Restore script for n8n deployment

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file not found!"
    exit 1
fi

# Stop all services
echo "Stopping all services..."
docker compose down

# Backup current state (just in case)
TIMESTAMP=$(date +%Y%m%d%H%M%S)
TEMP_BACKUP="./backups/pre_restore_${TIMESTAMP}.tar.gz"
mkdir -p ./backups
echo "Creating temporary backup of current state..."
tar -czf "${TEMP_BACKUP}" ./volumes/n8n ./volumes/postgres .env

# Extract backup
echo "Extracting backup..."
tar -xzf "${BACKUP_FILE}"

# Start all services
echo "Starting all services..."
docker compose up -d

echo "Restore completed. Previous state backed up to: ${TEMP_BACKUP}"
EOL

# Make scripts executable
chmod +x ./scripts/backup.sh ./scripts/restore.sh

# Create a simple health check script
echo "Creating health check script..."
cat > ./scripts/health_check.sh << 'EOL'
#!/bin/bash
# Health check script for n8n deployment

echo "===================================="
echo "        n8n Health Check            "
echo "===================================="

# Check if containers are running
echo -e "\nChecking container status:"
docker compose ps

# Check container logs (last 10 lines)
for service in traefik postgres redis n8n-primary n8n-worker n8n-webhook; do
  echo -e "\nLast 10 log lines for $service:"
  docker compose logs --tail=10 $service
done

# Check resource usage
echo -e "\nResource usage:"
docker stats --no-stream $(docker compose ps -q)

# Check Traefik dashboard access
echo -e "\nChecking Traefik dashboard access:"
source .env
curl -s -o /dev/null -w "%{http_code}" https://traefik.${DOMAIN}

echo -e "\nHealth check completed."
EOL

chmod +x ./scripts/health_check.sh

echo ""
echo "Setup completed successfully!"
echo "You can now start your n8n deployment by running:"
echo "  docker compose up -d"
echo ""
echo "Once started, n8n will be available at: https://${DOMAIN}"
echo "Traefik dashboard will be available at: https://traefik.${DOMAIN}"
echo ""
echo "For maintenance, you can use the following scripts:"
echo "  ./scripts/backup.sh - Create a backup"
echo "  ./scripts/restore.sh - Restore from backup"
echo "  ./scripts/health_check.sh - Check deployment health"
echo ""
