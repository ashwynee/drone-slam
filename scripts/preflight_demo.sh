#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo; echo "PRECHECK FAILED: $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

echo "=== Drone-SLAM preflight ==="
echo "Checking paths, ROS packages, available storage, and old processes."
echo

for path in \
  "$HOME/PX4-Autopilot/Tools/simulation/gz/worlds/walls.sdf" \
  "$HOME/PX4-Autopilot/Tools/simulation/gz/models/x500_mono_cam/model.sdf" \
  "$HOME/px4_ros2_ws/install/setup.bash" \
  "$HOME/ORB_SLAM3/lib/libORB_SLAM3.so" \
  "$HOME/ORB_SLAM3/Vocabulary/ORBvoc.txt" \
  "$HOME/ORB_SLAM3/Examples/Monocular/Drone320.yaml" \
  "$HOME/drone-slam/scripts/record_gt.py"; do
  [[ -r "$path" ]] || fail "Required file missing/unreadable: $path"
done
ok "Required project files and local ground-truth recorder exist."

command -v gz >/dev/null 2>&1 || fail "Gazebo CLI 'gz' not found in PATH."
command -v timeout >/dev/null 2>&1 || fail "GNU timeout command not found."
ok "Gazebo CLI and timeout are available."

home_free="$(df -Pm "$HOME" | awk 'NR==2 {print $4}')"
[[ "$home_free" =~ ^[0-9]+$ ]] || fail "Could not read free space for $HOME."
if (( home_free < 2048 )); then
  fail "Only ${home_free} MB free on the WSL filesystem; at least 2048 MB is required. Free space before starting PX4 because its logger previously reported I/O errors."
fi
ok "WSL filesystem has ${home_free} MB available."

if [[ -d /mnt/c ]]; then
  c_free="$(df -Pm /mnt/c | awk 'NR==2 {print $4}')"
  if [[ "$c_free" =~ ^[0-9]+$ ]] && (( c_free < 2048 )); then
    fail "Only ${c_free} MB free on Windows C:. Free at least 2048 MB before starting this simulation."
  fi
  [[ "$c_free" =~ ^[0-9]+$ ]] && ok "Windows C: has ${c_free} MB available."
fi

for path in "$HOME/PX4-Autopilot" "$HOME/px4_ros2_ws" "$HOME/drone-slam"; do
  [[ -w "$path" ]] || fail "Not writable: $path"
done
touch "$HOME/PX4-Autopilot/.drone_slam_write_test" 2>/dev/null || fail "Cannot write to PX4-Autopilot; investigate WSL storage/I/O errors."
rm -f "$HOME/PX4-Autopilot/.drone_slam_write_test"
ok "Project directories pass a write test."

# Do not kill old processes automatically; duplicate SITL instances can corrupt logs or compete for simulator ports.
existing="$(pgrep -af '[p]x4_sitl_default|[m]ake px4_sitl|[g]z sim|[o]rbslam3_node|[p]arameter_bridge|[r]ecord_gt.py' || true)"
if [[ -n "$existing" ]]; then
  echo "$existing"
  fail "Existing PX4/Gazebo/ROS demo processes are still running. Close the old demo windows cleanly, then run the launcher again."
fi
ok "No duplicate PX4/Gazebo/ROS demo processes found."

source /opt/ros/humble/setup.bash || fail "Could not source ROS 2 Humble."
source "$HOME/px4_ros2_ws/install/setup.bash" || fail "Could not source the px4_ros2_ws overlay."
ros2 pkg executables orbslam3_ros 2>/dev/null | grep -Eq '(^|[[:space:]])orbslam3_node$' || fail "ROS executable orbslam3_ros/orbslam3_node is not installed in the workspace."
source /opt/ros/humble/setup.bash
ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1 || fail "ROS package ros_gz_bridge is not available."
ok "ROS 2 Humble, ros_gz_bridge, and orbslam3_node are available."

wsl_ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')"
if [[ -n "$wsl_ip" ]]; then
  echo
  echo "Current WSL eth0 IP: $wsl_ip"
  echo "QGroundControl's WSL UDP link must point to this IP on port 18570."
fi

echo
echo "PRECHECK PASSED. No vehicle arming or movement was commanded."
