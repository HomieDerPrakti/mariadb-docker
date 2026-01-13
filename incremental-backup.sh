#!/bin/bash

set -euo pipefail
BACKUP_ROOT=/mnt/backup
DATE="$(date +%Y-%m-%d)"
LOG="${BACKUP_ROOT}/log-inc-${DATE}"

echo "[$(date +%H:%M:%S)] Mounting NFS share..."
sudo mount /mnt/backup

LATEST_WEEK=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'week-*' | sort | tail -n 1 )
target_dir="${LATEST_WEEK}/inc-${DATE}"
DEFAULTS="/var/mariadb-backup/.my.cnf"
backup_ok=0

cleanup() {
    if findmnt -t nfs,nfs4 /mnt/backup >/dev/null; then
        if [[ $backup_ok == "0" ]]; then
            echo "[$(date +%H:%M:%S)] Cleaning up files..." | tee -a $LOG
            rm -rf $target_dir
            echo "[$(date +%H:%M:%S)] Unmounting NFS share..." | tee -a $LOG
            sudo umount /mnt/backup
            exit 1
        fi
        echo "[$(date +%H:%M:%S)] Unmounting NFS share..." | tee -a $LOG
        sudo umount /mnt/backup
    fi
}

trap cleanup EXIT

last_base="$(
    find "$LATEST_WEEK" -maxdepth 1 -type d -name 'inc-*' | sort | tail -n 1 || true
)"

if [[ -z $last_base ]]; then
    last_base=$(
        find "$LATEST_WEEK" -maxdepth 1 -type d -name 'full-*' | sort | tail -n 1 || true
    )
fi

if [[ -z $last_base ]]; then
    echo "[$(date +%H:%M:%S)] No backup base found. Make a full backup first." | tee -a $LOG
    exit 1
fi

if [[ -e $target_dir ]]; then
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

echo "[$(date +%H:%M:%S)] Starting INCREMENTAL backup to $target_dir" | tee -a $LOG
echo "[$(date +%H:%M:%S)] Based on: $last_base"

mariadb-backup \
    --defaults-extra-file=$DEFAULTS \
    --backup \
    --target-dir=$target_dir \
    --incremental-basedir=$last_base \
    --history=$DATE \
    2>&1 | tee -a "$LOG"

echo "[$(date +%H:%M:%S)] Incremental backup OK."
backup_ok=1
echo "[$(date +%H:%M:%S)] Done"