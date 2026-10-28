#!/usr/bin/env bash
set -Eeuo pipefail
source /opt/ros/humble/setup.bash
topic='/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image'
echo "Waiting up to 90 seconds for an actual ROS camera message..."
for ((i=1; i<=30; i++)); do
  if timeout 2s ros2 topic echo "$topic" --once --qos-profile sensor_data >/dev/null 2>&1; then
    echo "[OK] ROS camera messages are arriving: $topic"
    exit 0
  fi
  sleep 1
done
echo "ERROR: ROS camera messages did not arrive within 90 seconds." >&2
echo "Check the ROS 2 Camera Bridge window and verify that QGroundControl/Gazebo remain running." >&2
exit 1
