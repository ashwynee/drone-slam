#!/usr/bin/env bash
# PX4 health gate for the Drone-SLAM one-click launcher.
# Avoid 'set -e' here so a failed diagnostic command never exits silently.
set -uo pipefail

readonly PX4_HEALTH_VERSION="2026-10-29.13"
LOG="$HOME/drone-slam/results/live_gazebo/px4_console.log"

fail() {
  echo
  echo "PX4 HEALTH CHECK FAILED: $*" >&2
  if [[ -f "$LOG" ]]; then
    echo >&2
    echo "===== Last 45 lines of PX4 console log =====" >&2
    tail -n 45 "$LOG" >&2 || true
    echo "===== End PX4 console excerpt =====" >&2
    echo "Full log: $LOG" >&2
  else
    echo "PX4 console log not found: $LOG" >&2
  fi
  exit 1
}

echo "PX4 health checker v$PX4_HEALTH_VERSION"
echo "Waiting up to 180 seconds for this run's PX4 startup marker and Ready for takeoff..."
ready=0
process_seen=0
for ((i=1; i<=180; i++)); do
  # Never trust a readiness line unless the current-run sentinel is present in the same log.
  if [[ -f "$LOG" ]] && grep -Fq 'DRONE-SLAM PX4 RUN STARTED UTC=' "$LOG" && grep -Fq 'Ready for takeoff!' "$LOG"; then
    ready=1
    break
  fi

  if pgrep -x px4 >/dev/null 2>&1; then
    process_seen=1
  elif (( i >= 20 )) && (( process_seen == 0 )); then
    fail "PX4/Gazebo process did not appear within 20 seconds. Check the PX4 + Gazebo window."
  elif (( process_seen == 1 )) && (( i >= 20 )); then
    # If the process disappeared after having been seen, report failure instead of
    # waiting the full timeout on a stale log.
    if ! pgrep -x px4 >/dev/null 2>&1; then
      fail "PX4/Gazebo process exited before reporting Ready for takeoff."
    fi
  fi
  sleep 1
done

[[ "$ready" -eq 1 ]] || fail "This run did not report Ready for takeoff within 180 seconds. The sentinel and PX4 output above show what actually started."

# Use awk for line selection. grep | tail | cut can raise SIGPIPE under pipefail
# when the PX4 console contains many repeated status lines.
ready_line="$(awk '/DRONE-SLAM PX4 RUN STARTED UTC=/ { run_start=NR } run_start > 0 && /Ready for takeoff!/ { if (first == 0) first=NR } END { if (first > 0) print first }' "$LOG")"
[[ "$ready_line" =~ ^[0-9]+$ ]] || fail "Could not locate the PX4 readiness marker in the console log."

echo "[OK] PX4 reported Ready for takeoff! Checking sensor, storage, and GCS status..."
sleep 10

if ! pgrep -x px4 >/dev/null 2>&1; then
  fail "PX4/Gazebo exited during the health check."
fi

if grep -Eiq 'logger.*write failed|dataman.*file read failed|dataman_client.*readSync failed' "$LOG"; then
  io_errors="$(grep -Ei 'logger.*write failed|dataman.*file read failed|dataman_client.*readSync failed' "$LOG" || true)"
  fail "PX4 logged filesystem/DataManager I/O errors. The storage problem must be resolved before continuing:
$io_errors"
fi

# A localhost-only warning may refer to another MAVLink instance. The decisive
# GCS gate is the newest commander/preflight GCS event below; keep the warning
# in the failure log excerpt instead of rejecting a healthy GCS connection.

sensor_errors="$(awk -v start="$ready_line" 'NR >= start && /Accel #0 fail:.*TIMEOUT|Preflight Fail: ekf2 missing data/ { print }' "$LOG")"
if [[ -n "$sensor_errors" ]]; then
  fail "PX4 logged accelerometer timeout or EKF missing-data errors after readiness:
$sensor_errors"
fi

# The startup preflight warning often occurs before the GCS MAVLink instance
# starts. Only treat GCS warnings after the Normal GCS MAVLink instance comes up
# as a current failure; QGC's current visible link state is the fallback check.
mavlink_line="$(awk 'index($0, "[mavlink] mode: Normal") > 0 { print NR; exit }' "$LOG")"
[[ "$mavlink_line" =~ ^[0-9]+$ ]] || fail "PX4 did not log startup of its Normal GCS MAVLink instance."

gcs_status="$(awk -v start="$mavlink_line" '
  NR >= start && /Preflight Fail: No connection to the GCS/ { status="FAILED"; line=NR }
  NR >= start && /Connection to ground station lost/ { status="LOST"; line=NR }
  NR >= start && /GCS connection regained/ { status="CONNECTED"; line=NR }
  END { if (status != "") printf "%s %d\n", status, line }
' "$LOG")"

if [[ -z "$gcs_status" ]]; then
  echo "[WARN] PX4 did not print an explicit post-start GCS connection transition in its console log."
  echo "The earlier preflight warning occurred before MAVLink startup; this alone does not prove that the link is still down."
  echo "The launcher will ask you to confirm the vehicle is visible in QGroundControl before it starts the ROS pipeline."
else
  case "$gcs_status" in
    CONNECTED*)
      echo "[OK] PX4 logged a GCS connection after MAVLink startup: $gcs_status"
      ;;
    *)
      fail "PX4 reports an unhealthy GCS link after MAVLink started (latest event: $gcs_status). Confirm QGroundControl's UDP link uses Port 18570 and Server Address WSL-IP:18570 as described by PX4's WSL guide, then click Connect and verify the vehicle appears."
      ;;
  esac
fi

echo "[OK] PX4 process remains running; no post-readiness sensor/EKF or storage errors were found."
echo "PX4 health check passed. This does not mean the vehicle is armed or that SLAM is initialized."
exit 0
