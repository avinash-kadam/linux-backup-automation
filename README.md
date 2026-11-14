# Linux Backup & Recovery Automation on AWS

Automated nightly MySQL and config backups to an NFS server, with retention,
a tested restore process, and Prometheus + Alertmanager alerts to Slack.

## Architecture

    app-server (MySQL + Nginx, cron + backup.sh)
        |  NFS (port 2049)            |  metrics (port 9100)
        v                             v
    nfs-server (/backups)       monitor-server (Prometheus + Alertmanager) -> Slack

## Tech stack
AWS EC2 (Ubuntu 24.04), NFS, MySQL, Bash, Cron, Prometheus,
Alertmanager, node_exporter (textfile collector), Slack webhooks, Git

## How it works
1. `scripts/backup.sh` dumps MySQL, archives /etc/nginx, compresses and verifies the files.
2. Files are copied to the NFS share (the script checks the share is mounted first).
3. Retention: 7 days of daily backups, 28 days of weekly backups.
4. The script writes metrics (status, timestamp, size) for node_exporter.
5. Prometheus alerts on failed backups, missing backups (25h) and a down server.

## Cron (server clock is UTC, this is 2 AM IST)

    30 20 * * * /home/ubuntu/backup-project/scripts/backup.sh >> /home/ubuntu/cron.log 2>&1

## How to restore

    ./scripts/restore.sh /mnt/backups/daily/db_<TIMESTAMP>.sql.gz shopdb

## Testing
- Dropped the database on purpose and restored it from backup.
- Broke the script on purpose and received a Slack alert.

## Screenshots
See the docs/ folder.

## What I learned
- A backup you have never restored is only a hope.
- Check the NFS mount before writing, or the local disk fills up.
- Monitor for backups that do not run, not only ones that fail.
- Keep secrets (passwords, webhooks) out of Git.

## Security
No passwords or webhook URLs are stored in this repo.
