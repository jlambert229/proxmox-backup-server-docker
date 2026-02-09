#!/bin/bash
set -euo pipefail

NAS_HOST="${NAS_HOST:-192.168.2.129}"
NAS_USER="${NAS_USER:-jlambert}"
NAS_DOCKER_DIR="/volume1/docker/pbs"
NAS_BACKUP_DIR="/volume1/backups/proxmox"

echo "=== Deploying Proxmox Backup Server on Synology NAS ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

step() {
    echo -e "${GREEN}==>${NC} $1"
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

fail() {
    echo -e "${RED}❌${NC} $1"
    exit 1
}

ok() {
    echo -e "${GREEN}✅${NC} $1"
}

# Check prerequisites
step "1/7: Preflight checks"

info "Testing SSH to ${NAS_HOST}..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${NAS_USER}@${NAS_HOST}" "true" 2>/dev/null; then
    fail "Cannot SSH to ${NAS_HOST}. Check key auth and connectivity."
fi
ok "SSH connection"

info "Checking for Docker on NAS..."
if ! ssh "${NAS_USER}@${NAS_HOST}" "command -v docker" &>/dev/null; then
    fail "Docker not found on NAS. Install Container Manager from Package Center."
fi
ok "Docker is installed"

echo ""

# Create directories on NAS
step "2/7: Creating directories on NAS"
ssh "${NAS_USER}@${NAS_HOST}" "sudo mkdir -p ${NAS_DOCKER_DIR}/{etc,lib} ${NAS_BACKUP_DIR} && sudo chown -R \$(id -u):\$(id -g) ${NAS_DOCKER_DIR} ${NAS_BACKUP_DIR}" || fail "Failed to create directories"
ok "Directories created"
echo ""

# Prompt for PBS admin password
step "3/7: Configuration"

if [[ ! -f .env ]]; then
    info "Creating .env file..."
    cp .env.example .env
    
    echo ""
    echo "Set PBS admin password (user: admin, realm: pbs):"
    read -s -p "Password: " PBS_PASSWORD
    echo ""
    read -s -p "Confirm: " PBS_PASSWORD_CONFIRM
    echo ""
    
    if [[ "$PBS_PASSWORD" != "$PBS_PASSWORD_CONFIRM" ]]; then
        fail "Passwords do not match"
    fi
    
    if [[ -z "$PBS_PASSWORD" ]]; then
        fail "Password cannot be empty"
    fi
    
    # Update .env
    sed -i "s/^PBS_PASSWORD=.*/PBS_PASSWORD=${PBS_PASSWORD}/" .env
    ok "Configuration saved to .env"
else
    info ".env already exists, using existing configuration"
fi

echo ""

# Copy files to NAS
step "4/7: Copying files to NAS"
ssh "${NAS_USER}@${NAS_HOST}" "mkdir -p ${NAS_DOCKER_DIR}"
scp -q docker-compose.yml .env "${NAS_USER}@${NAS_HOST}:${NAS_DOCKER_DIR}/" || fail "Failed to copy files"
ok "Files copied"
echo ""

# Pull image and start PBS
step "5/7: Pulling PBS image and starting container"
ssh "${NAS_USER}@${NAS_HOST}" "cd ${NAS_DOCKER_DIR} && docker-compose pull" || fail "Failed to pull image"
ssh "${NAS_USER}@${NAS_HOST}" "cd ${NAS_DOCKER_DIR} && docker-compose up -d" || fail "Failed to start container"
ok "PBS container started"
echo ""

# Wait for PBS to be ready
step "6/7: Waiting for PBS to be ready"
info "PBS takes ~30 seconds to start..."
for i in {1..30}; do
    if ssh "${NAS_USER}@${NAS_HOST}" "docker logs proxmox-backup-server 2>&1 | grep -q 'starting task'" 2>/dev/null; then
        break
    fi
    sleep 1
done
ok "PBS is starting"
echo ""

# Verify PBS is accessible
step "7/7: Verifying deployment"
info "Testing PBS web UI..."
if curl -k -s -o /dev/null -w "%{http_code}" "https://${NAS_HOST}:8007" | grep -q "200\|302"; then
    ok "PBS web UI is accessible"
else
    info "⚠️  PBS web UI not responding yet. It may still be initializing."
fi
echo ""

# Summary
step "Deployment complete!"
echo ""
echo "Access Proxmox Backup Server:"
echo "  https://${NAS_HOST}:8007"
echo ""
echo "Login credentials:"
echo "  User: admin"
echo "  Realm: pbs"
echo "  Password: (from .env file)"
echo ""
echo "⚠️  Browser will warn about self-signed certificate - this is expected."
echo ""
echo "Next steps:"
echo "  1. Log in to PBS web UI"
echo "  2. Create datastore: Datastore → Add Datastore"
echo "     - Name: proxmox-vms"
echo "     - Path: /mnt/datastore"
echo "  3. Configure retention policy and GC schedule"
echo "  4. In Proxmox VE: Add PBS as storage (see README.md)"
echo ""
echo "Check logs:"
echo "  ssh ${NAS_USER}@${NAS_HOST} 'docker logs proxmox-backup-server'"
