#!/usr/bin/env bash
# ============================================================================
# WordPress Docker Backup Script
# ============================================================================
# Creates timestamped backups of the database and WordPress files.
# Keeps the last N backups (default: 7) with automatic rotation.
#
# Usage:
#   bash scripts/backup.sh              # Manual backup
#   crontab -e                           # Automated backup
#   0 3 * * * /path/to/scripts/backup.sh # Daily at 3 AM
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
KEEP_BACKUPS=${KEEP_BACKUPS:-7}

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Load environment ──────────────────────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found. Run setup.sh first."
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# ── Pre-checks ────────────────────────────────────────────────────────────
COMPOSE_NAME="${COMPOSE_PROJECT_NAME:-wordpress-site}"
DB_CONTAINER="${COMPOSE_NAME}-db"

if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    log_error "Database container '${DB_CONTAINER}' is not running."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

# ── Database Backup ──────────────────────────────────────────────────────
log_info "Backing up database..."

DB_BACKUP_FILE="$BACKUP_DIR/${COMPOSE_NAME}_db_${TIMESTAMP}.sql.gz"

docker exec "$DB_CONTAINER" \
    mysqldump \
    -u root \
    -p"${MYSQL_ROOT_PASSWORD}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    "${MYSQL_DATABASE}" \
    2>/dev/null \
    | gzip > "$DB_BACKUP_FILE"

if [ -s "$DB_BACKUP_FILE" ]; then
    DB_SIZE=$(du -h "$DB_BACKUP_FILE" | cut -f1)
    log_ok "Database backup: $DB_BACKUP_FILE ($DB_SIZE)"
else
    log_error "Database backup failed or is empty."
    rm -f "$DB_BACKUP_FILE"
    exit 1
fi

# ── WordPress Files Backup ───────────────────────────────────────────────
log_info "Backing up WordPress files..."

WP_BACKUP_FILE="$BACKUP_DIR/${COMPOSE_NAME}_files_${TIMESTAMP}.tar.gz"
WP_VOLUME="${COMPOSE_NAME}_wordpress_data"

docker run --rm \
    -v "${WP_VOLUME}:/data:ro" \
    -v "$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/$(basename "$WP_BACKUP_FILE")" -C /data .

if [ -s "$WP_BACKUP_FILE" ]; then
    WP_SIZE=$(du -h "$WP_BACKUP_FILE" | cut -f1)
    log_ok "Files backup: $WP_BACKUP_FILE ($WP_SIZE)"
else
    log_error "WordPress files backup failed or is empty."
    rm -f "$WP_BACKUP_FILE"
    exit 1
fi

# ── Rotate Old Backups ───────────────────────────────────────────────────
log_info "Rotating backups (keeping last $KEEP_BACKUPS)..."

# Rotate DB backups
DB_COUNT=$(find "$BACKUP_DIR" -name "${COMPOSE_NAME}_db_*.sql.gz" -type f | wc -l)
if [ "$DB_COUNT" -gt "$KEEP_BACKUPS" ]; then
    find "$BACKUP_DIR" -name "${COMPOSE_NAME}_db_*.sql.gz" -type f \
        | sort \
        | head -n -"$KEEP_BACKUPS" \
        | xargs rm -f
    log_ok "Rotated DB backups."
fi

# Rotate file backups
FILES_COUNT=$(find "$BACKUP_DIR" -name "${COMPOSE_NAME}_files_*.tar.gz" -type f | wc -l)
if [ "$FILES_COUNT" -gt "$KEEP_BACKUPS" ]; then
    find "$BACKUP_DIR" -name "${COMPOSE_NAME}_files_*.tar.gz" -type f \
        | sort \
        | head -n -"$KEEP_BACKUPS" \
        | xargs rm -f
    log_ok "Rotated file backups."
fi

# ── Summary ───────────────────────────────────────────────────────────────
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
echo -e "\n${GREEN}Backup complete!${NC} Total backup storage: $TOTAL_SIZE"
