#!/usr/bin/env bash
# ============================================================================
# WordPress Docker Setup Script
# ============================================================================
# Generates .env with secure random passwords from .env.example
# Usage: bash scripts/setup.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Functions ──────────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# ── Pre-checks ─────────────────────────────────────────────────────────────
echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WordPress Docker Infrastructure - Setup${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}\n"

if ! command -v openssl &> /dev/null; then
    log_error "openssl is required but not installed."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "docker is required but not installed."
    exit 1
fi

# ── Check for existing .env ───────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
    log_warn ".env file already exists at: $ENV_FILE"
    read -rp "Overwrite? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_info "Aborted. Existing .env was not modified."
        exit 0
    fi
fi

# ── Generate secure passwords ─────────────────────────────────────────────
log_info "Generating secure passwords..."

MYSQL_ROOT_PASS=$(generate_password)
MYSQL_USER_PASS=$(generate_password)
REDIS_PASS=$(generate_password)

log_ok "Passwords generated."

# ── Create .env from template ─────────────────────────────────────────────
if [ ! -f "$ENV_EXAMPLE" ]; then
    log_error ".env.example not found at: $ENV_EXAMPLE"
    exit 1
fi

log_info "Creating .env from template..."

cp "$ENV_EXAMPLE" "$ENV_FILE"

# Replace placeholder passwords
sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}|" "$ENV_FILE"
sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${MYSQL_USER_PASS}|" "$ENV_FILE"
sed -i "s|WORDPRESS_DB_PASSWORD=.*|WORDPRESS_DB_PASSWORD=${MYSQL_USER_PASS}|" "$ENV_FILE"
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASS}|" "$ENV_FILE"

# Set secure file permissions
chmod 600 "$ENV_FILE"

log_ok ".env created with secure passwords at: $ENV_FILE"

# ── Create required directories ───────────────────────────────────────────
log_info "Creating directories..."
mkdir -p "$PROJECT_DIR/backups"
log_ok "Directories created."

# ── Check proxy network ──────────────────────────────────────────────────
PROXY_NETWORK=$(grep "^PROXY_NETWORK=" "$ENV_FILE" | cut -d'=' -f2)
if ! docker network ls --format '{{.Name}}' | grep -q "^${PROXY_NETWORK}$"; then
    log_warn "Docker network '${PROXY_NETWORK}' does not exist."
    read -rp "Create it now? (Y/n): " create_net
    if [[ ! "$create_net" =~ ^[nN]$ ]]; then
        docker network create "$PROXY_NETWORK"
        log_ok "Network '${PROXY_NETWORK}' created."
    else
        log_warn "You must create the network before running docker compose up."
        log_info "Run: docker network create ${PROXY_NETWORK}"
    fi
else
    log_ok "Docker network '${PROXY_NETWORK}' exists."
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e ""
echo -e "  ${BLUE}Next steps:${NC}"
echo -e "  1. Review and customize: ${YELLOW}nano .env${NC}"
echo -e "  2. Update COMPOSE_PROJECT_NAME and PROXY_NETWORK"
echo -e "  3. Build and start:      ${YELLOW}docker compose up -d --build${NC}"
echo -e "  4. Check health:         ${YELLOW}docker compose ps${NC}"
echo -e "  5. Configure in NPM:     Point your domain to container '${YELLOW}\${COMPOSE_PROJECT_NAME}-nginx${NC}' port 80"
echo -e ""
echo -e "  ${RED}IMPORTANT:${NC} Your passwords are in .env — keep this file secure!"
echo -e ""
