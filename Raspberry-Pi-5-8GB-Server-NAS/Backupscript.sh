#!/bin/bash

# Remote incremental backup script (Pi 5 -> Pi 2) using rsync snapshots with --link-dest and retention.
#
# Workflow (SMART disabled):
#  1) Create a timestamped partial snapshot directory on the remote
#  2) Push data from LOCAL_DIR to remote partial using rsync with --link-dest=remote:latest (if exists)
#  3) Atomically finalize the snapshot and update the 'latest' symlink
#  4) Apply retention on the remote (delete snapshots older than RETENTION_DAYS)
#  5) Log all steps; abort retention if rsync failed

set -euo pipefail
IFS=$'\n\t'

########################################
# User-configurable settings
########################################

# Local source to back up
LOCAL_DIR="/mnt/NAS"

# Remote destination (host and path)
REMOTE_USER="user"
REMOTE_HOST="nasbackup.local"
REMOTE_PORT="22"               # change if not 22
REMOTE_BASE="/mnt/nasbackup"   # remote base directory for all snapshots

# SSH key
PRIVATE_KEY="/path/to/private/key"

# Retention in days (8 weeks ~ 56 days)
RETENTION_DAYS=56

# Optional exclude file on Pi 5
EXCLUDES_FILE=""               # e.g., "/home/pi/backup_excludes.txt"

# Logging
LOG_DIR="${HOME}/.local/var/log/incremental-backup"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%F_%H-%M-%S)"
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

########################################
# Derived paths and helpers
########################################

REMOTE_SSH_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
SSH_OPTS=(-p "$REMOTE_PORT" -i "$PRIVATE_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
SSH_CMD=(ssh "${SSH_OPTS[@]}")
RSYNC_SSH="ssh -p ${REMOTE_PORT} -i '${PRIVATE_KEY}' -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

REMOTE_SNAPSHOTS_DIR="${REMOTE_BASE}/snapshots"
REMOTE_LATEST_LINK="${REMOTE_BASE}/latest"
SNAPSHOT_NAME="Backup_${TIMESTAMP}"
REMOTE_SNAPSHOT_FINAL="${REMOTE_SNAPSHOTS_DIR}/${SNAPSHOT_NAME}"
REMOTE_SNAPSHOT_PARTIAL="${REMOTE_SNAPSHOT_FINAL}.partial"

log() {
    local level="$1"; shift
    local msg="$*"
    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" | tee -a "$LOG_FILE"
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log ERROR "Required command '$cmd' not found. Aborting."
            exit 1
        fi
    done
}

cleanup_on_error() {
    local exit_code=$?
    log ERROR "Backup failed with exit code $exit_code"
    # Leave remote partial in place for inspection; remove on next successful run if desired
    exit "$exit_code"
}

trap cleanup_on_error ERR

########################################
# Backup process
########################################

main() {
    require_cmd rsync ssh date find

    log INFO "==== Backup run started ===="

    # 1) Prepare remote directories
    log INFO "Ensuring remote snapshot directories exist: ${REMOTE_SNAPSHOTS_DIR}"
    "${SSH_CMD[@]}" "$REMOTE_SSH_TARGET" "mkdir -p '$REMOTE_SNAPSHOTS_DIR' '$REMOTE_SNAPSHOT_PARTIAL'"

    # 2) Rsync to remote partial with optional --link-dest=latest
    local link_opts=()
    if "${SSH_CMD[@]}" "$REMOTE_SSH_TARGET" "test -e '$REMOTE_LATEST_LINK'"; then
        link_opts=("--link-dest=$REMOTE_LATEST_LINK")
        log INFO "Using --link-dest=$REMOTE_LATEST_LINK"
    else
        log INFO "No 'latest' found on remote; full copy will be made"
    fi

    local exclude_opts=()
    if [[ -n "${EXCLUDES_FILE}" && -f "${EXCLUDES_FILE}" ]]; then
        exclude_opts=("--exclude-from=${EXCLUDES_FILE}")
        log INFO "Using exclude file ${EXCLUDES_FILE}"
    fi

    log INFO "Starting rsync to ${REMOTE_SNAPSHOT_PARTIAL}"
    rsync \
        -aHAX \
        --numeric-ids \
        --delete \
        --delete-excluded \
        --human-readable \
        --info=stats2 \
        --partial \
        -e "$RSYNC_SSH" \
        "${link_opts[@]}" \
        "${exclude_opts[@]}" \
        -- "${LOCAL_DIR%/}/" "${REMOTE_SSH_TARGET}:${REMOTE_SNAPSHOT_PARTIAL}/" |& tee -a "$LOG_FILE"

    log INFO "Rsync completed successfully"

    # 3) Atomically finalize snapshot and update 'latest'
    log INFO "Finalizing snapshot and updating 'latest'"
    "${SSH_CMD[@]}" "$REMOTE_SSH_TARGET" \
        "mv '$REMOTE_SNAPSHOT_PARTIAL' '$REMOTE_SNAPSHOT_FINAL' && ln -sfn '$REMOTE_SNAPSHOT_FINAL' '$REMOTE_LATEST_LINK'"

    # 4) Apply retention on remote (AFTER successful rsync)
    log INFO "Applying retention: removing snapshots older than ${RETENTION_DAYS} days"
    "${SSH_CMD[@]}" "$REMOTE_SSH_TARGET" \
        "find '$REMOTE_SNAPSHOTS_DIR' -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -print -exec rm -rf {} +" | tee -a "$LOG_FILE"

    log INFO "==== Backup run completed successfully ===="
}

main "$@"