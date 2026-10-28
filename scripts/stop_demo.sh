#!/usr/bin/env bash
set -Eeuo pipefail

# Stop only processes belonging to this Drone-SLAM PX4/Gazebo demo.
# Do not stop QGroundControl or unrelated Gazebo worlds.
patterns=(
  '[o]rbslam3_node'
  '[p]arameter_bridge.*world/walls/model/x500_mono_cam_0'
  '[r]ecord_gt.py'
  '[p]x4_sitl_default'
  '[g]z sim.*walls'
  '[m]ake px4_sitl gz_x500_mono_cam_walls'
)

matches() {
  local pattern
  for pattern in "${patterns[@]}"; do
    pgrep -af "$pattern" || true
  done
}

echo "=== Stop existing Drone-SLAM processes ==="
before="$(matches)"
if [[ -z "$before" ]]; then
  echo "[OK] No existing Drone-SLAM processes found."
  exit 0
fi

echo "Sending Ctrl-C equivalent (SIGINT) to old project processes:"
echo "$before"
for pattern in "${patterns[@]}"; do
  pkill -INT -f "$pattern" 2>/dev/null || true
done
sleep 4

remaining="$(matches)"
if [[ -n "$remaining" ]]; then
  echo "Some processes are still running; asking them to terminate:"
  echo "$remaining"
  for pattern in "${patterns[@]}"; do
    pkill -TERM -f "$pattern" 2>/dev/null || true
  done
  sleep 3
fi

remaining="$(matches)"
if [[ -n "$remaining" ]]; then
  echo >&2
  echo "STOP FAILED: these matching processes remain:" >&2
  echo "$remaining" >&2
  echo "Close their terminal windows manually before trying again. No force-kill was used." >&2
  exit 1
fi

echo "[OK] Old Drone-SLAM processes stopped. QGroundControl and unrelated worlds were left alone."
