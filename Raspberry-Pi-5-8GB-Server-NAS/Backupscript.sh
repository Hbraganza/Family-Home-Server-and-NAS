#!/usr/bin/env bash

# Pi5 <-> Pi2 backup orchestration script
#
# Workflow:
#  1) (Optional) Send Wake-on-LAN to Pi 2 and turn on smart plugs (placeholders)
#  2) Wait for Pi 2 to be online (SSH available)
#  3) Start SMART short tests on both Pi 5 and Pi 2 drives, wait for results
#  4) If SMART bad on either, send email and abort
#  5) Perform incremental rsync backup from Pi 2 -> Pi 5 using --link-dest snapshots
#  6) Notify Pi 2 of completion and shut it down
#  7) Confirm Pi 2 is down, then (placeholder) turn off smart plugs
#
# Requirements on Pi 5: bash, ssh, rsync, smartctl (smartmontools), date, find, mail/sendmail(optional)
# Requirements on Pi 2: sshd, rsync, smartctl (smartmontools), sudo for shutdown (or adjust REMOTE_SHUTDOWN_CMD)

set -euo pipefail
IFS=$'\n\t'

########################################
# User-configurable settings
########################################

# Remote (Pi 2)
PI2_HOST="raspberrypi2.local"     # or IP
PI2_USER="admin"                 # SSH user on Pi 2 (as per your setup)
PI2_SSH_PORT="22"                # SSH port for Pi 2
SSH_KEY_PATH="/home/pi/.ssh/id_ed25519"  # Path to private key on Pi 5 used for admin@Pi2
PI2_MAC=""                        # e.g. "AA:BB:CC:DD:EE:FF" if WoL is supported; leave empty to skip

# What to back up (directories on Pi 5, local sources)
# Example: ("/mnt/data") — trailing slash handled by rsync call
LOCAL_SOURCE_DIRS=("/mnt/data")

# Remote backup root on Pi 2 (destination on remote)
# e.g., "/mnt/backupdrive/pi5" — snapshots will live under ${REMOTE_BACKUP_ROOT}/snapshots
REMOTE_BACKUP_ROOT="/mnt/backupdrive/pi5"

# Optional exclude file (on Pi 5) to pass to rsync --exclude-from
EXCLUDES_FILE=""                  # e.g. "/srv/backups/excludes.txt" or leave empty

# SMART devices to test
# Local (Pi 5) example: ("/dev/sda" "/dev/sdb")
SMART_DEVICES_LOCAL=("/dev/sda")
# Remote (Pi 2) example: ("/dev/sda") — adjust per your disks
SMART_DEVICES_REMOTE=("/dev/sda")

# Retention in days (8 weeks ~ 56 days)
RETENTION_DAYS=56

# Email notifications (optional)
EMAIL_TO=""                       # e.g. "you@example.com"; leave empty to disable email
EMAIL_FROM="pi5-backup@local"

# Remote shutdown command (adjust if not using sudo or path differs)
REMOTE_SHUTDOWN_CMD="sudo /sbin/shutdown -h now"

# Optional: use sudo for remote rsync reads (if needed to read all files)
REMOTE_RSYNC_PATH="rsync"         # or "sudo rsync" if necessary

########################################
# Internal defaults and helpers
########################################

# Local logging only
LOG_DIR="/var/log/pi5-pi2-backup"
mkdir -p "$LOG_DIR"

# Remote snapshot locations (on Pi 2)
REMOTE_SNAPSHOTS_DIR="${REMOTE_BACKUP_ROOT}/snapshots"
REMOTE_LATEST_LINK="${REMOTE_BACKUP_ROOT}/latest"
TIMESTAMP="$(date +%F_%H-%M-%S)"
REMOTE_DEST_SNAPSHOT_DIR="${REMOTE_SNAPSHOTS_DIR}/${TIMESTAMP}"
REMOTE_DEST_PARTIAL_DIR="${REMOTE_DEST_SNAPSHOT_DIR}.partial"

SSH_OPTS=(
	-p "$PI2_SSH_PORT"
	-i "$SSH_KEY_PATH"
	-o BatchMode=yes
	-o StrictHostKeyChecking=accept-new
	-o ConnectTimeout=10
)

# For rsync's -e, provide a single string command
SSH_CMD="ssh -p $PI2_SSH_PORT -i '$SSH_KEY_PATH' -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

RSYNC_BASE_OPTS=(
	-aHAX
	--numeric-ids
	--delete
	--delete-excluded
	--human-readable
	--info=stats2
	--partial
)

LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

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

send_email() {
	local subject="$1"; shift
	local body="$*"
	if [[ -z "${EMAIL_TO}" ]]; then
		log INFO "EMAIL_TO not set; skipping email: $subject"
		return 0
	fi
	if command -v mail >/dev/null 2>&1; then
		printf "%s\n" "$body" | mail -s "$subject" -aFrom:"$EMAIL_FROM" "$EMAIL_TO" || true
		log INFO "Sent email via mail to $EMAIL_TO: $subject"
	elif command -v sendmail >/dev/null 2>&1; then
		{
			printf "From: %s\n" "$EMAIL_FROM"
			printf "To: %s\n" "$EMAIL_TO"
			printf "Subject: %s\n\n" "$subject"
			printf "%s\n" "$body"
		} | sendmail -t || true
		log INFO "Sent email via sendmail to $EMAIL_TO: $subject"
	else
		log WARN "No mail/sendmail found; cannot send email: $subject"
	fi
}

wol_send() {
	# Placeholder: Try to send WOL if MAC provided and tool is available
	if [[ -n "${PI2_MAC}" ]]; then
		if command -v wakeonlan >/dev/null 2>&1; then
			log INFO "Sending Wake-on-LAN using wakeonlan to $PI2_MAC"
			wakeonlan "$PI2_MAC" || log WARN "wakeonlan command failed"
		elif command -v etherwake >/dev/null 2>&1; then
			log INFO "Sending Wake-on-LAN using etherwake to $PI2_MAC"
			sudo etherwake "$PI2_MAC" || log WARN "etherwake command failed (requires root)"
		else
			log INFO "WoL tool not found; skipping WoL"
		fi
	else
		log INFO "PI2_MAC not set; skipping WoL"
	fi
}

smart_plug_on() {
	# Placeholder for smart plug power ON
	log INFO "[placeholder] Smart plug ON (no-op)"
}

smart_plug_off() {
	# Placeholder for smart plug power OFF
	log INFO "[placeholder] Smart plug OFF (no-op)"
}

ssh_pi2() {
	ssh "${SSH_OPTS[@]}" "$PI2_USER@$PI2_HOST" "$@"
}

wait_for_pi2_online() {
	log INFO "Waiting for Pi 2 ($PI2_HOST) SSH to be available..."
	local attempt=0
	until ssh_pi2 'echo "Pi2 online"' >/dev/null 2>&1; do
		attempt=$((attempt+1))
		if (( attempt % 6 == 0 )); then
			log INFO "Still waiting for Pi 2... (attempt $attempt)"
		fi
		sleep 5
	done
	log INFO "Pi 2 is online and reachable via SSH."
}

smart_estimate_seconds() {
	# Parse smartctl '-t short' output to get suggested wait time; default 120s
	local output="$1"
	local secs
	secs=$(grep -Eo 'Please wait [0-9]+ seconds' <<<"$output" | grep -Eo '[0-9]+' || true)
	if [[ -n "$secs" ]]; then
		echo "$secs"
	else
		echo 120
	fi
}

smart_run_short_local() {
	local dev="$1"
	log INFO "Starting SMART short test (local) on $dev"
	local out
	if ! out=$(sudo smartctl -t short "$dev" 2>&1); then
		log ERROR "Failed to start SMART short test on $dev: $out"
		return 1
	fi
	local wait_secs
	wait_secs=$(smart_estimate_seconds "$out")
	log INFO "Waiting ${wait_secs}s for SMART test on $dev"
	sleep "$wait_secs"
}

smart_run_short_remote() {
	local dev="$1"
	log INFO "Starting SMART short test (remote) on $dev"
	local out
	if ! out=$(ssh_pi2 "sudo smartctl -t short '$dev'" 2>&1); then
		log ERROR "Failed to start remote SMART short test on $dev: $out"
		return 1
	fi
	local wait_secs
	wait_secs=$(smart_estimate_seconds "$out")
	log INFO "Waiting ${wait_secs}s (remote) for SMART test on $dev"
	sleep "$wait_secs"
}

smart_health_local() {
	local dev="$1"
	local out
	if ! out=$(sudo smartctl -H "$dev" 2>&1); then
		log ERROR "smartctl -H failed on $dev: $out"
		return 1
	fi
	if grep -qi 'PASSED' <<<"$out"; then
		log INFO "SMART health PASSED (local) on $dev"
		return 0
	else
		log ERROR "SMART health NOT PASSED (local) on $dev: $out"
		return 2
	fi
}

smart_health_remote() {
	local dev="$1"
	local out
	if ! out=$(ssh_pi2 "sudo smartctl -H '$dev'" 2>&1); then
		log ERROR "remote smartctl -H failed on $dev: $out"
		return 1
	fi
	if grep -qi 'PASSED' <<<"$out"; then
		log INFO "SMART health PASSED (remote) on $dev"
		return 0
	else
		log ERROR "SMART health NOT PASSED (remote) on $dev: $out"
		return 2
	fi
}

run_smart_checks() {
	local any_fail=0

	# Start tests in sequence and wait per device (simple, predictable). Alternatively start all, then max wait.
	local d
	for d in "${SMART_DEVICES_LOCAL[@]}"; do
		smart_run_short_local "$d" || any_fail=1
		smart_health_local "$d" || any_fail=1
	done
	for d in "${SMART_DEVICES_REMOTE[@]}"; do
		smart_run_short_remote "$d" || any_fail=1
		smart_health_remote "$d" || any_fail=1
	done

	if (( any_fail != 0 )); then
		return 1
	fi
	return 0
}

rsync_backup() {
	log INFO "Starting rsync snapshot backup from Pi 5 to Pi 2"

	# Ensure remote rsync exists and create remote partial destination
	if ! ssh_pi2 "command -v rsync >/dev/null"; then
		log ERROR "rsync not found on Pi 2. Please install rsync."
		return 1
	fi
	ssh_pi2 "mkdir -p '$REMOTE_DEST_PARTIAL_DIR'" || {
		log ERROR "Failed to create remote partial directory $REMOTE_DEST_PARTIAL_DIR"
		return 1
	}

	local rsync_dest="$PI2_USER@$PI2_HOST:$REMOTE_DEST_PARTIAL_DIR/"
	local link_dest_opts=()
	# Use remote latest as link-dest (evaluated on destination)
	ssh_pi2 "test -e '$REMOTE_LATEST_LINK'" && link_dest_opts=("--link-dest=$REMOTE_LATEST_LINK")
	if [[ ${#link_dest_opts[@]} -gt 0 ]]; then
		log INFO "Using --link-dest=$REMOTE_LATEST_LINK"
	fi

	local excludes_opts=()
	if [[ -n "${EXCLUDES_FILE}" && -f "${EXCLUDES_FILE}" ]]; then
		excludes_opts=("--exclude-from=${EXCLUDES_FILE}")
		log INFO "Using exclude file ${EXCLUDES_FILE}"
	fi

	# Build local source list with trailing slashes to copy contents
	local sources=()
	local src
	for src in "${LOCAL_SOURCE_DIRS[@]}"; do
		sources+=("${src%/}/")
	done

	# Run rsync pushing to remote destination
	if ! rsync \
			-e "$SSH_CMD" \
			--rsync-path="$REMOTE_RSYNC_PATH" \
			"${RSYNC_BASE_OPTS[@]}" \
			"${link_dest_opts[@]}" \
			"${excludes_opts[@]}" \
			-- "${sources[@]}" "$rsync_dest"; then
		log ERROR "rsync failed"
		return 1
	fi

	# Atomically finalize snapshot and update latest symlink on remote
	ssh_pi2 "mv '$REMOTE_DEST_PARTIAL_DIR' '$REMOTE_DEST_SNAPSHOT_DIR' && ln -sfn '$REMOTE_DEST_SNAPSHOT_DIR' '$REMOTE_LATEST_LINK'" || {
		log ERROR "Failed to finalize snapshot on remote"
		return 1
	}
	log INFO "Snapshot created at $REMOTE_DEST_SNAPSHOT_DIR on Pi 2 and latest updated"
}

apply_retention() {
	log INFO "Applying retention on Pi 2: delete snapshots older than ${RETENTION_DAYS} days"
	ssh_pi2 "find '$REMOTE_SNAPSHOTS_DIR' -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -print -exec rm -rf '{}' +" | tee -a "$LOG_FILE" || true
}

confirm_pi2_shutdown() {
	log INFO "Waiting for Pi 2 to shut down..."
	local tries=0
	while true; do
		if ! ssh_pi2 'true' >/dev/null 2>&1; then
			log INFO "SSH unreachable; Pi 2 appears down."
			break
		fi
		tries=$((tries+1))
		if (( tries > 60 )); then
			log WARN "Timed out waiting for Pi 2 shutdown"
			break
		fi
		sleep 5
	done
}

cleanup_on_error() {
	local exit_code=$?
	# Attempt to clean remote partial snapshot if it exists
	ssh_pi2 "test -d '$REMOTE_DEST_PARTIAL_DIR' && rm -rf '$REMOTE_DEST_PARTIAL_DIR' || true" || true
	log ERROR "Script failed with exit code $exit_code"
	exit "$exit_code"
}

trap cleanup_on_error ERR

main() {
	require_cmd ssh rsync smartctl date find

	log INFO "==== Backup run started ===="

	# Step 1: Wake / Power On (placeholders)
	smart_plug_on
	wol_send

	# Step 2: Wait for Pi 2 online (announcement via first SSH echo)
	wait_for_pi2_online

	# Step 3: SMART tests on both Pis
	if (( ${#SMART_DEVICES_LOCAL[@]} == 0 && ${#SMART_DEVICES_REMOTE[@]} == 0 )); then
		log WARN "No SMART devices configured; skipping SMART checks"
	else
		if ! run_smart_checks; then
			log ERROR "SMART checks indicate problems. Aborting backup."
			send_email "[Pi5] Backup aborted: SMART failure" \
				"One or more SMART checks failed. See log: $LOG_FILE"
			# Inform Pi 2 and avoid shutdown in case it should remain on
			ssh_pi2 "echo 'Pi5: SMART failure, backup aborted'" || true
			return 1
		fi
		log INFO "SMART checks passed on all configured devices"
	fi

		# Step 4/5: Perform rsync incremental backup with --link-dest (Pi 5 -> Pi 2)
	rsync_backup

	# Step 6: Notify completion to Pi 2
	ssh_pi2 "echo 'Pi5: backup completed at ${TIMESTAMP}'" || true

    # Step 7: Apply retention policy (on Pi 2)
	apply_retention

	# Step 8: Ask Pi 2 to shutdown and confirm
	ssh_pi2 "$REMOTE_SHUTDOWN_CMD" || log WARN "Failed to send remote shutdown command"
	confirm_pi2_shutdown

	# Step 9: Power off smart plugs (placeholder)
	smart_plug_off

	log INFO "==== Backup run completed successfully ===="
}

main "$@"

# Usage notes:
#  - Edit the config section above to match your environment.
#  - Ensure passwordless SSH from Pi 5 -> Pi 2 is configured for $PI2_USER@$PI2_HOST.
#  - Ensure smartmontools and rsync are installed on both Pis.
#  - For remote shutdown, configure passwordless sudo for shutdown or adjust REMOTE_SHUTDOWN_CMD.
#  - Create the backup root on Pi 5 and make this script executable:
#      chmod +x Backupscript.sh
#  - Run manually or via cron/systemd timer on Pi 5.

