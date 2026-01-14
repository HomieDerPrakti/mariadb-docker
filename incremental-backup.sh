#!/bin/bash

set -euo pipefail
DEFAULTS="/var/mariadb-backup/.my.cnf"
BACKUP_ROOT=/mnt/backup
DATE="$(date +%Y-%m-%d)"
LOG="${BACKUP_ROOT}/log-inc-${DATE}.txt"
backup_ok=0
target_dir=""
LATEST_WEEK=""

echo "[$(date +%H:%M:%S)] Mounting NFS share..."
{ 
    findmnt -t nfs,nfs4 /mnt/backup >/dev/null 2>&1 && echo "[$(date +%H:%M:%S)] NFS share already mounted."; 
} || { 
    sudo mount /mnt/backup && echo "[$(date +%H:%M:%S)] NFS share successfully mounted."; 
}

cleanup() {
    if findmnt -t nfs,nfs4 /mnt/backup >/dev/null 2>&1; then
        if [[ $backup_ok == "0" || -z "$LATEST_WEEK" ]]; then
            echo "[$(date +%H:%M:%S)] Cleaning up files..." | tee -a "$LOG"
            [[ ! -z "$target_dir" ]] && rm -rf "$target_dir"
            mkdir -p "${BACKUP_ROOT}/error-logs/"
            mv "$LOG" "${BACKUP_ROOT}/error-logs/error-log-inc-${DATE}.txt"
            echo "[$(date +%H:%M:%S)] Unmounting NFS share..." | tee -a "${BACKUP_ROOT}/error-logs/error-log-inc-${DATE}.txt"
            sudo umount /mnt/backup
            return
        else
            mkdir -p "${LATEST_WEEK}/logs"
            mv "$LOG" "${LATEST_WEEK}/logs/log-inc-${DATE}.txt"
            echo "[$(date +%H:%M:%S)] Unmounting NFS share..." | tee -a "${LATEST_WEEK}/logs/log-inc-${DATE}.txt"
            sudo umount /mnt/backup
        fi
    fi
}

trap cleanup EXIT

LATEST_WEEK=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'week-*' 2>/dev/null | sort -V | tail -n 1 )
[[ -z "$LATEST_WEEK" ]] && {
    echo "[$(date +%H:%M:%S)] No Week directory found. Please make a full backup first"
    exit 1
}
target_dir="${LATEST_WEEK}/inc-${DATE}"

last_base="$(
    find "$LATEST_WEEK" -maxdepth 1 -type d -name 'inc-*' 2>/dev/null | sort -V | tail -n 1 || true
)"

if [[ -z "$last_base" ]]; then
    last_base="$(
        find "$LATEST_WEEK" -maxdepth 1 -type d -name 'full-*' 2>/dev/null | sort -V | tail -n 1 || true
    )"
fi

if [[ -z "$last_base" ]]; then
    echo "[$(date +%H:%M:%S)] No backup base found. Make a full backup first." | tee -a "$LOG"
    exit 1
fi

if [[ -e "$target_dir" ]]; then
    num=1
    while :; do 
        if [[ -e "${target_dir}_${num}" ]]; then
            num=$((num+1))
            continue
        else
            target_dir="${target_dir}_${num}"
            break
        fi
    done
fi

echo "[$(date +%H:%M:%S)] Starting INCREMENTAL backup to $target_dir" | tee -a "$LOG"
echo "[$(date +%H:%M:%S)] Based on: $last_base" | tee -a "$LOG"

mariadb-backup \
    --defaults-extra-file="$DEFAULTS" \
    --backup \
    --target-dir="$target_dir" \
    --incremental-basedir="$last_base" \
    --history="$DATE" \
    2>&1 | tee -a "$LOG"

echo "[$(date +%H:%M:%S)] Incremental backup OK." | tee -a "$LOG"
backup_ok=1
echo "[$(date +%H:%M:%S)] Done" | tee -a "$LOG"