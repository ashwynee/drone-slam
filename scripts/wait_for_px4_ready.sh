#!/usr/bin/env bash
# PX4 health gate for the Drone-SLAM one-click launcher.
# Avoid 'set -e' here so a failed diagnostic command never exits silently.
set -uo pipefail

readonly PX4_HEALTH_VERSION="2026-10-29.6"
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
echo "Waiting up to 180 seconds for PX4 to report Ready for takeoff..."
ready=0
for ((i=1; i<=180; i++)); do
  if [[ -f "$LOG" ]] && grep -Fq 'Ready for takeoff!' "$LOG"; then
    ready=1
    break
  fi

  if ! pgrep -af '[m]ake px4_sitl gz_x500_mono_cam_walls|[p]x4_sitl_default' >/dev/null 2>&1; then
    fail "PX4/Gazebo exited before reporting Ready for takeoff."
  fi
  sleep 1
done

[[ "$ready" -eq 1 ]] || fail "PX4 did not report Ready for takeoff within 180 seconds."

# Use awk for line selection. grep | tail | cut can raise SIGPIPE under pipefail
# when the PX4 console contains many repeated status lines.
ready_line="$(awk '/Ready for takeoff!/ { last=NR } END { if (last > 0) print last }' "$LOG")"
[[ "$ready_line" =~ ^[0-9]+$ ]] || fail "Could not locate the PX4 readiness marker in the console log."

echo "[OK] PX4 reported Ready for takeoff! Checking sensor, storage, and GCS status..."
sleep 10

if ! pgrep -af '[m]ake px4_sitl gz_x500_mono_cam_walls|[p]x4_sitl_default' >/dev/null 2>&1; then
  fail "PX4/Gazebo exited during the health check."
fi

if grep -Eiq 'MAVLink only on localhost|logger.*write failed|dataman.*file read failed|dataman_client.*readSync failed' "$LOG"; then
  io_or_network_errors="$(grep -Ei 'MAVLink only on localhost|logger.*write failed|dataman.*file read failed|dataman_client.*readSync failed' "$LOG" || true)"
  fail "PX4 logged a localhost-only MAVLink or filesystem/DataManager I/O error. The network/storage issue must be resolved before continuing:
$io_or_network_errors"
fi

sensor_errors="$(awk -v start="$ready_line" 'NR >= start && /Accel #0 fail:.*TIMEOUT|Preflight Fail: ekf2 missing data/ { print }' "$LOG")"
if [[ -n "$sensor_errors" ]]; then
  fail "PX4 logged accelerometer timeout or EKF missing-data errors after readiness:
$sensor_errors"
fi

# Track the latest relevant GCS event in file order, without pipelines.
gcs_status="$(awk '
  /Preflight Fail: No connection to the GCS/ { status="FAILED"; line=NR }
  /Connection to ground station lost/ { status="LOST"; line=NR }
  /GCS connection regained/ { status="CONNECTED"; line=NR }
  END { if (status != "") printf "%s %d\n", status, line }
' "$LOG")"

if [[ -z "$gcs_status" ]]; then
  fail "PX4 did not log a confirmed GCS connection event. Opening QGroundControl is not enough; its WSL UDP link must actually connect to the current WSL IP on port 18570."
fi

case "$gcs_status" in
  CONNECTED\ *)
    echo "[OK] Latest PX4 GCS event: $gcs_status"
    ;;
  *)
    fail "PX4 still reports an unhealthy GCS link (latest event: $gcs_status). Confirm QGroundControl is connected to WSL eth0 IP on UDP 18570 and that the firewall permits the traffic."
    ;;
esac

echo "[OK] PX4 process remains running; no post-readiness sensor/EKF or storage errors were found."
echo "PX4 health check passed. This does not mean the vehicle is armed or that SLAM is initialized."
exit 0
