#!/bin/bash

set -euo pipefail

sudo mount /mnt/backup

echo "[$(date +%H:%M:%S)] Mounting NFS share"

BACKUP_ROOT=/mnt/backup/
DATE=$(date +%Y-%m-%d)
week_dir="${BACKUP_ROOT}/week-${DATE}"
DEFAULTS=/var/mariadb-backup/.my.cnf
LOG="${BACKUP_ROOT}/log-full-${DATE}"
backup_ok=0

num=1
if [[ -e "$week_dir" ]]; then
    while :; do
        if [[ -e "${week_dir}_${num}" ]]; then
            num=$((num+1))
            continue
        else
            week_dir="${week_dir}_${num}"
            break
        fi
    done
fi

TARGET_DIR="${week_dir}/full-${DATE}"

mkdir -p $TARGET_DIR

cleanup() {
    if findmnt -t nfs,nfs4 /mnt/backup >/dev/null; then
        if [[ $backup_ok == "0" ]]; then
            echo "[$(date +%H:%M:%S)] cleaning up files..." | tee -a "$LOG"
            rm -rf "${WEEK_DIR}/"
        fi
        echo "[$(date +%H:%M:%S)] unmonting NFS share" | tee -a "$LOG"
        sudo umount /mnt/backup
    fi
}

trap cleanup EXIT

echo "[$(date +%H:%M:%S)] Starting Backup to $TARGET_DIR" | tee -a "$LOG"

mariadb-backup \
    --defaults-extra-file="$DEFAULTS" \
    --backup \
    --target-dir="$TARGET_DIR" \
    --history="$DATE" \
    2>&1 | tee -a "$LOG"


#echo "[$(date +%H:%M:%S)] Preparing Backup" | tee -a "$LOG"
#
#mariadb-backup --prepare \
#    --target-dir="$TARGET_DIR" \
#    2>&1 | tee -a "$LOG"
#
#echo "[$(date +%H:%M:%S)] Preparing Backup OK" | tee -a "$LOG"
backup_ok=1

echo "[$(date +%H:%M:%S)] Done" | tee -a "$LOG"

