#!/usr/bin/env bash
set -Eeuo pipefail

LOG="$HOME/drone-slam/results/live_gazebo/px4_console.log"
echo "Waiting up to 180 seconds for PX4 to report Ready for takeoff..."
for ((i=1; i<=180; i++)); do
  if [[ -f "$LOG" ]] && grep -Fq 'Ready for takeoff!' "$LOG"; then
    echo "[OK] PX4 reported Ready for takeoff! Checking runtime health for 8 seconds..."
    sleep 8
    ready_line="$(grep -nF 'Ready for takeoff!' "$LOG" | tail -n 1 | cut -d: -f1)"
    [[ "$ready_line" =~ ^[0-9]+$ ]] || { echo "ERROR: Could not locate PX4 readiness marker in $LOG" >&2; exit 1; }
    post_ready="$(tail -n +"$ready_line" "$LOG")"

    errors="$(grep -Ei 'Accel #0 fail:.*TIMEOUT|logger.*write failed|dataman.*file read failed|dataman_client.*readSync failed|Preflight Fail: ekf2 missing data' <<< "$post_ready" || true)"
    if [[ -n "$errors" ]]; then
      echo "ERROR: PX4 reported sensor or filesystem/DataManager errors after readiness:" >&2
      echo "$errors" >&2
      echo "Do not arm. See the PX4 + Gazebo window and $LOG." >&2
      exit 1
    fi

    last_gcs_fail="$(grep -nF 'Preflight Fail: No connection to the GCS' "$LOG" | tail -n 1 | cut -d: -f1 || true)"
    last_gcs_regain="$(grep -nF 'GCS connection regained' "$LOG" | tail -n 1 | cut -d: -f1 || true)"
    last_gcs_lost="$(grep -nF 'Connection to ground station lost' "$LOG" | tail -n 1 | cut -d: -f1 || true)"
    if [[ "$last_gcs_fail" =~ ^[0-9]+$ ]] && { [[ ! "$last_gcs_regain" =~ ^[0-9]+$ ]] || (( last_gcs_fail > last_gcs_regain )); }; then
      echo "ERROR: PX4's latest GCS status is still failing." >&2
      echo "Check QGroundControl's UDP link/IP and port 18570. Current PX4 console: $LOG" >&2
      exit 1
    fi
    if [[ "$last_gcs_lost" =~ ^[0-9]+$ ]] && { [[ ! "$last_gcs_regain" =~ ^[0-9]+$ ]] || (( last_gcs_lost > last_gcs_regain )); }; then
      echo "ERROR: PX4's latest message says the GCS connection was lost." >&2
      echo "Check QGroundControl's UDP link/IP and port 18570." >&2
      exit 1
    fi

    echo "[OK] PX4 readiness and post-start sensor/filesystem/GCS checks passed."
    exit 0
  fi

  if ! pgrep -af '[m]ake px4_sitl gz_x500_mono_cam_walls|[p]x4_sitl_default' >/dev/null; then
    echo "ERROR: PX4/Gazebo process ended before reaching Ready for takeoff!" >&2
    [[ -f "$LOG" ]] && tail -n 35 "$LOG" >&2
    exit 1
  fi
  sleep 1
done

echo "ERROR: PX4 did not report Ready for takeoff within 180 seconds." >&2
[[ -f "$LOG" ]] && tail -n 35 "$LOG" >&2
exit 1
