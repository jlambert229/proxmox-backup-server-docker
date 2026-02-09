#!/bin/bash
set -euo pipefail

NAS_HOST="${NAS_HOST:-192.168.2.129}"
NAS_USER="${NAS_USER:-jlambert}"

echo "=== Verifying Proxmox Backup Server ==="
echo ""

# Check container is running
echo "Checking container status..."
if ssh "${NAS_USER}@${NAS_HOST}" "docker ps | grep proxmox-backup-server" &>/dev/null; then
    echo "✅ Container is running"
else
    echo "❌ Container is not running"
    echo ""
    echo "Check logs:"
    echo "  ssh ${NAS_USER}@${NAS_HOST} 'docker logs proxmox-backup-server'"
    exit 1
fi

# Check web UI is accessible
echo "Checking web UI..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${NAS_HOST}:8007" || echo "000")

if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "302" ]]; then
    echo "✅ Web UI is accessible (HTTP $HTTP_CODE)"
else
    echo "⚠️  Web UI returned HTTP $HTTP_CODE"
fi

# Check volumes are mounted
echo "Checking mounted volumes..."
for vol in "etc" "lib" "datastore"; do
    if ssh "${NAS_USER}@${NAS_HOST}" "docker exec proxmox-backup-server test -d /etc/proxmox-backup" &>/dev/null; then
        echo "✅ Volume mounted: /etc/proxmox-backup"
        break
    fi
done

echo ""
echo "=== Verification complete ==="
echo ""
echo "Access PBS:"
echo "  https://${NAS_HOST}:8007"
echo ""
echo "Check logs:"
echo "  ssh ${NAS_USER}@${NAS_HOST} 'docker logs proxmox-backup-server'"
