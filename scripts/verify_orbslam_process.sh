#!/usr/bin/env bash
set -Eeuo pipefail
echo "Checking whether the ORB-SLAM3 ROS node stays running..."
for ((i=1; i<=12; i++)); do
  if pgrep -af '[o]rbslam3_node' >/dev/null; then
    echo "[OK] ORB-SLAM3 ROS node process is running."
    echo "Tracking success is not assumed: inspect the ORB-SLAM3 window for tracking state 2."
    exit 0
  fi
  sleep 1
done
echo "ERROR: orbslam3_node did not remain running after startup." >&2
echo "Check the ORB-SLAM3 window for its startup error." >&2
exit 1
