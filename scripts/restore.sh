#!/usr/bin/env bash
# Usage: restore.sh <backup.sql.gz> [target_db]
set -euo pipefail
FILE="${1:?Usage: restore.sh <backup.sql.gz> [target_db]}"
TARGET_DB="${2:-shopdb_restored}"

gzip -t "$FILE"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$TARGET_DB\`;"
gunzip -c "$FILE" | sudo mysql "$TARGET_DB"
sudo mysql -e "SELECT COUNT(*) AS rows_restored FROM \`$TARGET_DB\`.customers;"
echo "Restore into '$TARGET_DB' completed."
