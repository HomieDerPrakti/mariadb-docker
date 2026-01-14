#!/bin/bash

set -euo pipefail

DATE=$(date +%Y-%m-%d)
BACKUP_ROOT=/mnt/backup
LOG="${BACKUP_ROOT}/log-full-${DATE}.txt"

echo "[$(date +%H:%M:%S)] Mounting NFS share..."
{ 
    findmnt -t nfs,nfs4 /mnt/backup >/dev/null && echo "[$(date +%H:%M:%S)] NFS share already mounted." | tee -a "$LOG"; 
} || { 
    sudo mount /mnt/backup && echo "[$(date +%H:%M:%S)] NFS share successfully mounted." | tee -a "$LOG"; 
}

week_dir="${BACKUP_ROOT}/week-${DATE}"
DEFAULTS=/var/mariadb-backup/.my.cnf
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

cleanup() {
    if findmnt -t nfs,nfs4 /mnt/backup >/dev/null 2>&1; then
        if [[ $backup_ok == "0" ]]; then
            echo "[$(date +%H:%M:%S)] cleaning up files..." | tee -a "$LOG"
            [[ -n "$week_dir" && "$week_dir" == "$BACKUP_ROOT"/week-* ]] && rm -rf "${week_dir}/"
            mkdir -p "${BACKUP_ROOT}/error-logs"
            mv "$LOG" "${BACKUP_ROOT}/error-logs/error-log-full-${DATE}.txt"
            echo "[$(date +%H:%M:%S)] Unmounting NFS share..." | tee -a "${BACKUP_ROOT}/error-logs/error-log-full-${DATE}.txt"
            sudo umount /mnt/backup
            return
        else
            mkdir -p "${week_dir}/logs"
            mv "$LOG" "${week_dir}/logs/log-full-${DATE}.txt"
            echo "[$(date +%H:%M:%S)] unmonting NFS share" | tee -a "${week_dir}/logs/log-full-${DATE}.txt"
            sudo umount /mnt/backup
        fi
    fi
}

trap cleanup EXIT

mkdir -p "$TARGET_DIR"

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