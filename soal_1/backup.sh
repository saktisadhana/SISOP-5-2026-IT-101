#!/bin/bash
set -e

apt install -y zip 2>/dev/null || true

# File harus SUDO
if [ "$EUID" -ne 0 ]; then
  echo "do sudo ./backup.sh u silly"
  exit 1
fi

TIMESTAMP=$(date +"%d%m%Y-%H%M%S")
BACKUP_FILE="osboot/farewell_backup_${TIMESTAMP}.zip"

echo "Creating backup: $BACKUP_FILE"

# Zip all build artifacts
zip "$BACKUP_FILE" \
    osboot/bzImage \
    osboot/single.gz \
    osboot/multi.gz \
    osboot/farewell.iso

# Remove original files after zipping
rm -f osboot/bzImage osboot/single.gz osboot/multi.gz osboot/farewell.iso

echo "Backup complete: $BACKUP_FILE"
