#!/bin/bash
# restore.sh - Restore script for n8n deployment with webhook processors

set -e

# Configuration
LOG_FILE="./backups/restore_log.txt"
TEMP_DIR=""

# Log function
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "${LOG_FILE}"
}

# Clean up function to be called on exit
cleanup() {
  if [ ! -z "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    log "Cleaning up temporary directory..."
    rm -rf "${TEMP_DIR}"
  fi
}

# Set trap for clean exit
trap cleanup EXIT

# Check arguments
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <backup_file.tar.gz>"
  echo "Example: $0 ./backups/n8n_backup_20250423120000.tar.gz"
  exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
  echo "Error: Backup file not found: ${BACKUP_FILE}"
  exit 1
fi

# Check if checksum file exists and verify
if [ -f "${BACKUP_FILE}.sha256" ]; then
  echo "Verifying backup file integrity..."
  if ! sha256sum --check "${BACKUP_FILE}.sha256"; then
    echo "Error: Backup file checksum verification failed!"
    echo "The backup file may be corrupted or modified."
    echo "Proceed anyway? (y/N)"
    read -r proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
      echo "Restore aborted."
      exit 1
    fi
  else
    echo "Backup file integrity verified."
  fi
else
  echo "Warning: Checksum file not found, skipping integrity check."
fi

# Create directory for logs if it doesn't exist
mkdir -p "$(dirname "${LOG_FILE}")"

log "Starting n8n restore process..."
log "Backup file: ${BACKUP_FILE}"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log "Created temporary directory: ${TEMP_DIR}"

# Extract the backup archive
log "Extracting backup archive..."
tar -xzf "${BACKUP_FILE}" -C "${TEMP_DIR}"
if [ $? -ne 0 ]; then
  log "Error: Failed to extract backup archive."
  exit 1
fi

# Check for manifest
if [ ! -f "${TEMP_DIR}/manifest.json" ]; then
  log "Warning: Backup manifest not found. This may not be a valid backup."
  echo "Proceed anyway? (y/N)"
  read -r proceed
  if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    log "Restore aborted by user."
    exit 1
  fi
fi

# Show backup information
if [ -f "${TEMP_DIR}/manifest.json" ]; then
  log "Backup information:"
  cat "${TEMP_DIR}/manifest.json" | tee -a "${LOG_FILE}"
fi

# Confirm restore
echo ""
echo "WARNING: This will replace your current n8n installation with the backup."
echo "All current data will be lost and replaced with the backup data."
echo ""
echo "Do you want to proceed? (yes/no)"
read -r confirmation
if [ "$confirmation" != "yes" ]; then
  log "Restore aborted by user."
  exit 1
fi

# Stop all services
log "Stopping all running services..."
docker compose down
if [ $? -ne 0 ]; then
  log "Warning: Failed to stop all services cleanly. Continuing anyway..."
fi

# Backup current state before restoring (just in case)
CURRENT_BACKUP="./backups/pre_restore_$(date +%Y%m%d%H%M%S).tar.gz"
log "Creating backup of current state: ${CURRENT_BACKUP}"
mkdir -p ./backups

if [ -d "./volumes" ]; then
  log "Backing up current volumes..."
  tar -czf "${CURRENT_BACKUP}" ./volumes .env docker-compose.yml 2>/dev/null || true
  log "Current state backed up to: ${CURRENT_BACKUP}"
else
  log "No existing volumes to back up."
fi

# Restore configuration files
log "Restoring configuration files..."
if [ -f "${TEMP_DIR}/docker-compose.yml" ]; then
  cp "${TEMP_DIR}/docker-compose.yml" ./docker-compose.yml
fi

if [ -f "${TEMP_DIR}/.env" ]; then
  cp "${TEMP_DIR}/.env" ./.env
fi

# Restore Traefik configuration
if [ -d "${TEMP_DIR}/traefik" ]; then
  log "Restoring Traefik configuration..."
  mkdir -p ./traefik
  cp -r "${TEMP_DIR}/traefik"/* ./traefik/
fi

# Restore volume data
log "Restoring volume data..."
mkdir -p ./volumes

# Restore n8n data
if [ -d "${TEMP_DIR}/volumes/n8n" ]; then
  log "Restoring n8n data..."
  rm -rf ./volumes/n8n 2>/dev/null || true
  mkdir -p ./volumes/n8n
  cp -r "${TEMP_DIR}/volumes/n8n"/* ./volumes/n8n/
else
  log "Warning: n8n data not found in the backup."
fi

# Restore Redis data
if [ -d "${TEMP_DIR}/volumes/redis" ] && [ -f "${TEMP_DIR}/volumes/redis/dump.rdb" ]; then
  log "Restoring Redis data..."
  mkdir -p ./volumes/redis
  cp "${TEMP_DIR}/volumes/redis/dump.rdb" ./volumes/redis/
else
  log "Warning: Redis data not found in the backup."
fi

# Restore Let's Encrypt certificates
if [ -d "${TEMP_DIR}/volumes/letsencrypt" ]; then
  log "Restoring Let's Encrypt certificates..."
  mkdir -p ./volumes/letsencrypt
  cp -r "${TEMP_DIR}/volumes/letsencrypt"/* ./volumes/letsencrypt/
fi

# Start the services
log "Starting services..."
docker compose up -d
if [ $? -ne 0 ]; then
  log "Error: Failed to start services."
  log "You may need to manually start them with: docker compose up -d"
  exit 1
fi

# Import PostgreSQL database
if [ -f "${TEMP_DIR}/n8n_database.sql" ]; then
  log "Waiting for PostgreSQL to start..."
  sleep 10  # Give PostgreSQL time to start

  log "Importing PostgreSQL database..."
  # Load environment variables
  set -a
  source .env
  set +a

  # Drop existing database and recreate
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE ${POSTGRES_DB};"
  
  # Import the database
  cat "${TEMP_DIR}/n8n_database.sql" | docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
  
  if [ $? -ne 0 ]; then
    log "Error: Failed to import PostgreSQL database."
    log "You may need to manually import it with: cat ${TEMP_DIR}/n8n_database.sql | docker compose exec -T postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
  else
    log "PostgreSQL database import completed."
  fi
else
  log "Warning: PostgreSQL database dump not found in the backup."
fi

# Restart n8n services
log "Restarting n8n services to apply changes..."
docker compose restart n8n-primary n8n-worker n8n-webhook
if [ $? -ne 0 ]; then
  log "Error: Failed to restart n8n services."
  log "Please restart them manually with: docker compose restart n8n-primary n8n-worker n8n-webhook"
fi

log "Restore process completed!"

echo ""
echo "=========================================================="
echo "                Restore Completed Successfully            "
echo "=========================================================="
echo "Your n8n instance has been restored from the backup."
echo ""
echo "A backup of your previous installation was created at:"
echo "${CURRENT_BACKUP}"
echo ""
echo "Please check the logs for any warnings or errors."
echo "Log file: ${LOG_FILE}"
echo ""
echo "You can now access your restored n8n instance at:"
source .env 2>/dev/null || true
if [ ! -z "${DOMAIN}" ]; then
  echo "https://${DOMAIN}"
else
  echo "http://localhost:5678 (or your configured domain)"
fi
echo "=========================================================="