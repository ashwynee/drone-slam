#!/usr/bin/env bash
# Target only this demo's actual processes. Do not use broad pgrep -af path
# fragments: CMake helper shells contain the PX4 binary path in their arguments.
readonly STOP_DEMO_VERSION="2026-10-29.7"
set -Eeuo pipefail

demo_pids() {
  ps -eo pid=,comm=,args= | awk '
    {
      pid = $1
      comm = $2
      args = $0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", args)

      if (comm == "px4") print pid
      else if (comm == "make" && args ~ /^make px4_sitl gz_x500_mono_cam_walls([[:space:]]|$)/) print pid
      else if (comm == "gz" && args ~ /^gz sim .*\/worlds\/walls\.sdf([[:space:]]|$)/) print pid
      else if (comm == "orbslam3_node") print pid
      else if (comm == "ros2" && args ~ /^ros2 run ros_gz_bridge parameter_bridge .*world\/walls\/model\/x500_mono_cam_0/) print pid
      else if ((comm == "python3" || comm == "python") && args ~ /\/drone-slam\/scripts\/record_gt\.py([[:space:]]|$)/) print pid
    }
  ' | sort -nu
}

show_pids() {
  local pids="$1"
  [[ -n "$pids" ]] || return 0
  ps -p "$(paste -sd, <<< "$pids")" -o pid=,comm=,args= 2>/dev/null || true
}

echo "=== Stop existing Drone-SLAM processes v$STOP_DEMO_VERSION ==="
before="$(demo_pids || true)"
if [[ -z "$before" ]]; then
  echo "[OK] No matching Drone-SLAM processes found."
  exit 0
fi

echo "Sending SIGINT to these exact project processes:"
show_pids "$before"
while read -r pid; do
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -INT "$pid" 2>/dev/null || true
done <<< "$before"
sleep 4

remaining="$(demo_pids || true)"
if [[ -n "$remaining" ]]; then
  echo "Some project processes remain; sending SIGTERM:"
  show_pids "$remaining"
  while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  done <<< "$remaining"
  sleep 3
fi

remaining="$(demo_pids || true)"
if [[ -n "$remaining" ]]; then
  echo >&2
  echo "STOP FAILED: these exact project processes remain:" >&2
  show_pids "$remaining" >&2
  echo "Close their terminal windows manually before retrying. No force-kill was used." >&2
  exit 1
fi

echo "[OK] Drone-SLAM PX4/Gazebo/ROS processes stopped. QGroundControl and unrelated CMake helper shells were left alone."
