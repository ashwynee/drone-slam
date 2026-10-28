#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo; echo "PRECHECK FAILED: $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

echo "=== Drone-SLAM preflight ==="
echo "Checking required paths, ROS packages, available storage, filesystem writeability, and duplicate processes."
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
if (( home_free < 4096 )); then
  fail "Only ${home_free} MB free on the WSL filesystem; at least 4096 MB is required for a fresh PX4/Gazebo run. Free space first because the previous run reported logger/dataman I/O errors."
fi
ok "WSL filesystem has ${home_free} MB available."

if [[ -d /mnt/c ]]; then
  c_free="$(df -Pm /mnt/c | awk 'NR==2 {print $4}')"
  if [[ "$c_free" =~ ^[0-9]+$ ]] && (( c_free < 4096 )); then
    fail "Only ${c_free} MB free on Windows C:. Free at least 4096 MB before starting this simulation."
  fi
  [[ "$c_free" =~ ^[0-9]+$ ]] && ok "Windows C: has ${c_free} MB available."
fi

for path in "$HOME/PX4-Autopilot" "$HOME/px4_ros2_ws" "$HOME/drone-slam"; do
  [[ -w "$path" ]] || fail "Not writable: $path"
done
write_test="$HOME/PX4-Autopilot/.drone_slam_write_test"
printf "drone-slam-write-test\\n" > "$write_test" 2>/dev/null || fail "Cannot write to PX4-Autopilot; investigate WSL storage/I/O errors."
grep -qx "drone-slam-write-test" "$write_test" 2>/dev/null || fail "WSL filesystem write/read test failed; do not start PX4 until storage is healthy."
rm -f "$write_test"
ok "PX4 repository write/read test passed."

# Do not kill old processes automatically; duplicate SITL instances can corrupt logs or compete for simulator ports.
existing="$(pgrep -af '[p]x4_sitl_default|[m]ake px4_sitl gz_x500_mono_cam_walls|[g]z sim.*walls|[o]rbslam3_node|[p]arameter_bridge.*world/walls/model/x500_mono_cam_0|[r]ecord_gt.py' || true)"
if [[ -n "$existing" ]]; then
  echo "$existing"
  fail "Existing PX4/Gazebo/ROS demo processes are still running. Close the old demo windows cleanly, then run the launcher again."
fi
ok "No duplicate PX4/Gazebo/ROS demo processes found."

source /opt/ros/humble/setup.bash || fail "Could not source ROS 2 Humble."
source "$HOME/px4_ros2_ws/install/setup.bash" || fail "Could not source the px4_ros2_ws overlay."
orb_executables="$(ros2 pkg executables orbslam3_ros 2>/dev/null || true)"
grep -Eq '(^|[[:space:]])orbslam3_node
source /opt/ros/humble/setup.bash
ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1 || fail "ROS package ros_gz_bridge is not available."
ok "ROS 2 Humble, ros_gz_bridge, and orbslam3_node are available."

ip4_details="$(ip -4 addr show eth0 2>/dev/null || true)"
wsl_ip="$(awk '/inet / {split($2,a,"/"); print a[1]; exit}' <<< "$ip4_details")"
if [[ -n "$wsl_ip" ]]; then
  echo
  echo "Current WSL eth0 IP: $wsl_ip"
  echo "QGroundControl's WSL UDP link must point to this IP on port 18570."
fi

echo
echo "PRECHECK PASSED. No vehicle arming or movement was commanded."
 <<< "$orb_executables" || fail "ROS executable orbslam3_ros/orbslam3_node is not installed in the workspace."
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
