#!/usr/bin/env bash
# Nightly backup: MySQL dump + nginx config -> NFS, with retention and metrics.
set -Eeuo pipefail

DB_NAME="shopdb"
DB_CNF="/home/ubuntu/.backup.cnf"
BACKUP_ROOT="/mnt/backups"
CONFIG_PATHS="etc/nginx"
LOG_FILE="/home/ubuntu/backup.log"
METRICS_FILE="/var/lib/node_exporter/textfile/backup.prom"
DAILY_KEEP_DAYS=7
WEEKLY_KEEP_DAYS=28
TS=$(date +%F_%H-%M)
TMP_DIR="/tmp/backup_$$"
DB_FILE="db_${TS}.sql.gz"
CFG_FILE="config_${TS}.tar.gz"

log() { echo "$(date '+%F %T') [$1] $2" | tee -a "$LOG_FILE"; }

write_metrics() {   # args: status(1/0) size_bytes
  local tmp="${METRICS_FILE}.$$"
  cat > "$tmp" <<EOF
# HELP backup_last_status 1 if the last backup succeeded, 0 if it failed
# TYPE backup_last_status gauge
backup_last_status $1
# HELP backup_last_run_timestamp_seconds Unix time of the last backup run
# TYPE backup_last_run_timestamp_seconds gauge
backup_last_run_timestamp_seconds $(date +%s)
# HELP backup_last_size_bytes Size of the last DB backup
# TYPE backup_last_size_bytes gauge
backup_last_size_bytes $2
EOF
  mv "$tmp" "$METRICS_FILE"
}

on_error() { log ERROR "Backup FAILED at line $1"; write_metrics 0 0; exit 1; }
cleanup()  { rm -rf "$TMP_DIR"; }
trap 'on_error $LINENO' ERR
trap cleanup EXIT

mkdir -p "$TMP_DIR"
log INFO "Backup started"

# 1. Make sure NFS is really mounted (otherwise we'd fill the local disk)
mountpoint -q "$BACKUP_ROOT" || { log ERROR "NFS not mounted"; write_metrics 0 0; exit 1; }
mkdir -p "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly"

# 2. Dump database and archive configs
mysqldump --defaults-extra-file="$DB_CNF" --single-transaction --no-tablespaces \
  --routines "$DB_NAME" | gzip > "$TMP_DIR/$DB_FILE"
tar -czf "$TMP_DIR/$CFG_FILE" -C / $CONFIG_PATHS

# 3. Copy to NFS
cp "$TMP_DIR/$DB_FILE" "$TMP_DIR/$CFG_FILE" "$BACKUP_ROOT/daily/"

# 4. Verify files exist, are non-empty and are valid gzip
for f in "$DB_FILE" "$CFG_FILE"; do
  [ -s "$BACKUP_ROOT/daily/$f" ] || { log ERROR "$f missing or empty"; false; }
  gzip -t "$BACKUP_ROOT/daily/$f"
done

# 5. Weekly copy every Sunday
if [ "$(date +%u)" = "7" ]; then
  cp "$BACKUP_ROOT/daily/$DB_FILE" "$BACKUP_ROOT/weekly/"
  log INFO "Weekly copy saved"
fi

# 6. Retention
find "$BACKUP_ROOT/daily"  -type f -mtime +"$DAILY_KEEP_DAYS"  -delete
find "$BACKUP_ROOT/weekly" -type f -mtime +"$WEEKLY_KEEP_DAYS" -delete

SIZE=$(stat -c%s "$BACKUP_ROOT/daily/$DB_FILE")
write_metrics 1 "$SIZE"
log INFO "Backup SUCCESS: $DB_FILE ($SIZE bytes)"
