#!/usr/bin/env bash
set -Eeuo pipefail
topic='/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image'
echo "Waiting up to 180 seconds for the Gazebo camera topic..."
for ((i=1; i<=180; i++)); do
  topics="$(gz topic -l 2>/dev/null || true)"
  if grep -Fxq "$topic" <<< "$topics"; then
    echo "[OK] Gazebo camera topic exists: $topic"
    exit 0
  fi
  sleep 1
done
echo "ERROR: Gazebo camera topic did not appear within 180 seconds." >&2
echo "Check the PX4/Gazebo window for startup or simulator errors. The launcher will stop here." >&2
exit 1
