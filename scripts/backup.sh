#!/bin/bash
# backup.sh - Comprehensive backup script for n8n deployment with webhook processors

set -e

# Configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
RETENTION_DAYS=7
LOG_FILE="${BACKUP_DIR}/backup_log.txt"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Log function
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "${LOG_FILE}"
}

log "Starting n8n backup process..."

# Load environment variables
if [ -f .env ]; then
  set -a
  source .env
  set +a
  log "Loaded environment variables from .env"
else
  log "Warning: .env file not found!"
fi

# Check for running containers
if ! docker compose ps | grep -q "n8n"; then
  log "Error: n8n containers are not running. Please start them before backup."
  exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log "Created temporary directory: ${TEMP_DIR}"

# Export PostgreSQL database
log "Exporting PostgreSQL database..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" > "${TEMP_DIR}/n8n_database.sql"
if [ $? -ne 0 ]; then
  log "Error: Failed to export PostgreSQL database."
  rm -rf "${TEMP_DIR}"
  exit 1
fi
log "PostgreSQL database export completed."

# Stop n8n services for consistent file backup
log "Stopping n8n services for consistent backup..."
docker compose stop n8n-primary n8n-worker n8n-webhook
if [ $? -ne 0 ]; then
  log "Error: Failed to stop n8n services."
  rm -rf "${TEMP_DIR}"
  exit 1
fi

# Copy configuration files
log "Copying configuration files..."
cp docker-compose.yml "${TEMP_DIR}/"
cp .env "${TEMP_DIR}/"
if [ -d "./traefik" ]; then
  cp -r ./traefik "${TEMP_DIR}/"
fi

# Backup volume data
log "Backing up volume data..."
mkdir -p "${TEMP_DIR}/volumes"
if [ -d "./volumes/n8n" ]; then
  cp -r ./volumes/n8n "${TEMP_DIR}/volumes/"
fi
if [ -d "./volumes/letsencrypt" ]; then
  cp -r ./volumes/letsencrypt "${TEMP_DIR}/volumes/"
fi

# Export Redis data
log "Exporting Redis data..."
# Create Redis backup script
cat > "${TEMP_DIR}/redis_backup.sh" << EOL
#!/bin/sh
redis-cli -a "${REDIS_PASSWORD}" --rdb /data/dump.rdb
EOL
chmod +x "${TEMP_DIR}/redis_backup.sh"

# Execute backup inside Redis container
docker compose exec -T redis sh -c "redis-cli -a \"${REDIS_PASSWORD}\" SAVE"
if [ $? -ne 0 ]; then
  log "Warning: Failed to save Redis data."
fi

# Copy Redis dump if it exists
if [ -f "./volumes/redis/dump.rdb" ]; then
  mkdir -p "${TEMP_DIR}/volumes/redis"
  cp ./volumes/redis/dump.rdb "${TEMP_DIR}/volumes/redis/"
  log "Redis data export completed."
else
  log "Warning: Redis dump.rdb not found."
fi

# Create backup manifest
log "Creating backup manifest..."
cat > "${TEMP_DIR}/manifest.json" << EOL
{
  "backup_name": "${BACKUP_NAME}",
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "n8n_version": "$(docker compose exec -T n8n-primary n8n --version || echo 'unknown')",
  "components": [
    "postgresql",
    "redis",
    "n8n-data",
    "configuration",
    "letsencrypt"
  ]
}
EOL

# Create the archive
log "Creating backup archive..."
tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .
if [ $? -ne 0 ]; then
  log "Error: Failed to create backup archive."
  # Restart n8n services even if backup fails
  docker compose start n8n-primary n8n-worker n8n-webhook
  rm -rf "${TEMP_DIR}"
  exit 1
fi

# Calculate checksum
log "Calculating backup checksum..."
sha256sum "${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"

# Restart n8n services
log "Restarting n8n services..."
docker compose start n8n-primary n8n-worker n8n-webhook
if [ $? -ne 0 ]; then
  log "Error: Failed to restart n8n services."
  log "Please restart them manually with: docker compose start n8n-primary n8n-worker n8n-webhook"
fi

# Clean up temporary directory
log "Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"

# Remove old backups
log "Checking for old backups to remove..."
find "${BACKUP_DIR}" -name "n8n_backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -exec rm {} \;
find "${BACKUP_DIR}" -name "n8n_backup_*.tar.gz.sha256" -type f -mtime +${RETENTION_DAYS} -exec rm {} \;

# Backup size
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

log "Backup completed successfully!"
log "Backup file: ${BACKUP_FILE}"
log "Backup size: ${BACKUP_SIZE}"
log "Backup checksum: $(cat "${BACKUP_FILE}.sha256")"

echo ""
echo "=========================================================="
echo "                 Backup Completed Successfully            "
echo "=========================================================="
echo "Backup file: ${BACKUP_FILE}"
echo "Backup size: ${BACKUP_SIZE}"
echo "Checksum file: ${BACKUP_FILE}.sha256"
echo ""
echo "To restore this backup, run:"
echo "./scripts/restore.sh ${BACKUP_FILE}"
echo ""
echo "Old backups older than ${RETENTION_DAYS} days have been removed."
echo "=========================================================="
