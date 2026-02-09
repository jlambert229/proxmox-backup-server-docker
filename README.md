# proxmox-backup-server-docker

Proxmox Backup Server running in Docker on Synology NAS for automated VM/container backups.

**Blog post:** [Automated Proxmox Backups with Proxmox Backup Server](https://foggyclouds.io/post/proxmox-backup-server/)

## Features

- **Incremental backups** - First backup is full, subsequent are diffs (fast + space-efficient)
- **Deduplication** - Multiple VMs with similar data share blocks
- **Compression** - zstd compression (fast + high ratio)
- **Verification** - Automated integrity checks
- **Web UI** - Browse backups, restore VMs with clicks
- **Scheduled jobs** - Cron-style automation from Proxmox

## Prerequisites

- Synology NAS with Docker support (DSM 7.x)
- SSH access to Synology
- Proxmox VE 8.x
- Static IP or reserved DHCP for PBS container

## Quick Start

```bash
# Clone the repo
git clone https://github.com/YOUR-USERNAME/proxmox-backup-server-docker.git
cd proxmox-backup-server-docker

# Deploy to Synology
./deploy.sh

# Verify
./verify.sh

# Access web UI
open https://192.168.2.129:8007
```

## What Gets Deployed

PBS runs as a Docker container on your Synology with:

- **Config volume:** `/volume1/docker/pbs/etc` → `/etc/proxmox-backup`
- **State volume:** `/volume1/docker/pbs/lib` → `/var/lib/proxmox-backup`
- **Datastore:** `/volume1/backups/proxmox` → `/mnt/datastore`
- **Web UI:** Port 8007 (HTTPS with self-signed cert)
- **Privileged:** Required for direct disk access (deduplication)

## Initial Configuration

### 1. Log In to PBS

```
URL: https://192.168.2.129:8007
User: admin
Realm: pbs
Password: (from .env file)
```

⚠️ Browser will warn about self-signed cert - this is expected. Click "Advanced" → "Proceed".

### 2. Create Datastore

**Datastore → Add Datastore**

```
Name: proxmox-vms
Path: /mnt/datastore
GC Schedule: daily at 03:00
Prune Schedule: daily at 04:00
Verify Schedule: weekly on Sunday at 05:00
```

**Retention Policy:**

```
Keep Last: 7
Keep Daily: 7
Keep Weekly: 4
Keep Monthly: 6
Keep Yearly: 2
```

This gives you:
- 7 days of daily backups
- 4 weeks of weekly backups
- 6 months of monthly backups
- 2 years of yearly backups

### 3. Create Backup User (Optional)

**Configuration → User Management → Add User**

```
Username: proxmox-backup
Realm: pbs
Email: proxmox@yourdomain.com
```

**Permissions → Add → User Permission**

```
Path: /datastore/proxmox-vms
User: proxmox-backup@pbs
Role: DatastoreBackup
```

**API Token:**

Configuration → Access Control → API Tokens → Add

```
User: proxmox-backup@pbs
Token ID: backup-token
```

Copy the token (shown once).

## Configure Proxmox VE

### 1. Add PBS as Storage

Proxmox Web UI → Datacenter → Storage → Add → Proxmox Backup Server

```
ID: pbs-synology
Server: 192.168.2.129
Username: admin@pbs (or proxmox-backup@pbs)
Password/Token: (from PBS)
Datastore: proxmox-vms
Fingerprint: (click "Scan")
```

### 2. Create Backup Job

**Datacenter → Backup → Add**

```
Node: pve
Storage: pbs-synology
Schedule: Daily at 02:00
Selection Mode: All
Compression: zstd
Mode: Snapshot
Protected: No
```

**Backup modes:**
- **Snapshot:** VM keeps running (preferred for most VMs)
- **Suspend:** VM paused during backup (ensures consistency)
- **Stop:** VM stopped, backed up, restarted (longest downtime)

### 3. Run Test Backup

**Datacenter → Backup → Select job → Run now**

Watch the task log. First backup is full (slow). Subsequent backups are incremental (fast).

Check PBS: **Datastore → proxmox-vms → Content**

You should see backup entries for each VM.

## Scheduled Backups

With the backup job configured, Proxmox automates everything:

- **Daily 2am:** Proxmox backs up all VMs to PBS
- **Daily 3am:** PBS runs garbage collection
- **Daily 4am:** PBS prunes old backups per retention policy
- **Weekly Sunday 5am:** PBS verifies chunk integrity

## Restore VMs

### Restore Entire VM

Proxmox UI → Storage → pbs-synology → Content

1. Select a VM backup
2. Click "Restore"
3. Choose VM ID (existing or new)
4. Click "Restore"

### Restore Single Disk

1. Storage → pbs-synology → Content → Select backup
2. Click "Show Configuration"
3. Select disk → "Restore"

### Disaster Recovery (New Proxmox Host)

1. Install Proxmox on new hardware
2. Add PBS storage (same config as before)
3. Storage → pbs-synology → Content → Restore VMs

PBS holds the backups. Proxmox hosts are disposable.

## Monitoring

### Email Notifications

PBS sends emails on backup completion/failure.

**Configuration → Administration → Email**

```
SMTP Server: smtp.gmail.com
Port: 587
Username: your-email@gmail.com
Password: (app-specific password)
```

Test: **Configuration → Email → Send Test Email**

### Check Backup Status

**Dashboard** shows:
- Last backup time
- Success/failure count
- Datastore usage
- Upcoming scheduled tasks

## Troubleshooting

### Container won't start

```bash
ssh jlambert@192.168.2.129
docker logs proxmox-backup-server
```

**Common issues:**
- Port 8007 already in use
- Volume permissions incorrect
- Insufficient privileges (needs `privileged: true`)

### Proxmox can't connect

**Check PBS is running:**

```bash
curl -k https://192.168.2.129:8007
# Should return HTML
```

**Check firewall:**

```bash
# On Synology
sudo iptables -L | grep 8007
```

**From Proxmox:**

```bash
curl -k https://192.168.2.129:8007
```

### Backup fails with "No space left"

**Check datastore usage:**

PBS UI → Datastore → proxmox-vms

- Used: X GB
- Available: Y GB

**Solutions:**

1. Run manual prune: Datastore → Prune & GC → Prune Now
2. Run garbage collection: Datastore → Prune & GC → GC Now
3. Adjust retention policy (keep fewer backups)
4. Expand NAS storage

### Verify job reports errors

**Check:**

```bash
ssh jlambert@192.168.2.129
docker logs proxmox-backup-server | grep -i verify
```

**Common causes:**
- Disk corruption (run Synology disk check)
- Interrupted backup (delete and re-run)

## Resource Usage

**PBS Docker container:**

- CPU: 5-10% during backup, <1% idle
- Memory: 500 MB - 1 GB
- Storage: ~500 MB (PBS image + config)

**Backup storage (example: 5 VMs, 200 GB total):**

| Backup # | Type | Size | Duration | Storage |
|----------|------|------|----------|---------|
| 1 | Full | 200 GB | 60 min | +80 GB (compressed+dedup) |
| 2 | Incremental | 10 GB | 10 min | +2 GB |
| 7 | Incremental | 15 GB | 12 min | +3 GB |

After 7 daily backups: ~100 GB used (50% savings from dedup+compression).

## Teardown

```bash
ssh jlambert@192.168.2.129
cd /volume1/docker/pbs
docker-compose down
```

To completely remove:

```bash
sudo rm -rf /volume1/docker/pbs
sudo rm -rf /volume1/backups/proxmox
```

⚠️ **Warning:** This deletes all backups. Copy backups elsewhere first.

## Security Notes

- PBS uses self-signed certificate (homelab use)
- For production: Configure proper TLS cert
- Don't expose PBS directly to internet
- Use strong admin password
- Consider API token instead of password for Proxmox

## References

- [Proxmox Backup Server Documentation](https://pbs.proxmox.com/docs/)
- [Proxmox VE Backup Guide](https://pve.proxmox.com/pve-docs/chapter-vzdump.html)
- [PBS Docker Image](https://hub.docker.com/r/proxmoxbackupserver/proxmox-backup-server)
- [Blog post: Automated Proxmox Backups](https://foggyclouds.io/post/proxmox-backup-server/)

## License

MIT
