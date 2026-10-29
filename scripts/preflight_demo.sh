#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo; echo "PRECHECK FAILED: $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

echo "=== Drone-SLAM preflight ==="
echo "Checking required paths, storage, filesystem writes, ROS packages, and duplicate processes."
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
ok "Required PX4, ROS workspace, ORB-SLAM3, config, and local recorder files exist."

command -v gz >/dev/null 2>&1 || fail "Gazebo CLI 'gz' not found in PATH."
command -v timeout >/dev/null 2>&1 || fail "GNU timeout command not found."
command -v curl >/dev/null 2>&1 || fail "curl is needed to refresh launcher helpers."
ok "Gazebo CLI, timeout, and curl are available."

home_free="$(df -Pm "$HOME" | awk 'NR==2 {print $4}')"
[[ "$home_free" =~ ^[0-9]+$ ]] || fail "Could not read free space for $HOME."
if (( home_free < 4096 )); then
  fail "Only $home_free MB free on the WSL filesystem; at least 4096 MB is required. Free space first because the previous run reported logger/DataManager I/O errors."
fi
ok "WSL filesystem has $home_free MB available."

if [[ -d /mnt/c ]]; then
  c_free="$(df -Pm /mnt/c | awk 'NR==2 {print $4}')"
  if [[ "$c_free" =~ ^[0-9]+$ ]] && (( c_free < 4096 )); then
    fail "Only $c_free MB free on Windows C:. Free at least 4096 MB before starting the simulation."
  fi
  if [[ "$c_free" =~ ^[0-9]+$ ]]; then ok "Windows C: has $c_free MB available."; fi
fi

for path in "$HOME/PX4-Autopilot" "$HOME/px4_ros2_ws" "$HOME/drone-slam"; do
  [[ -w "$path" ]] || fail "Not writable: $path"
done

write_test="$HOME/PX4-Autopilot/.drone_slam_write_test"
printf "drone-slam-write-test\n" > "$write_test" 2>/dev/null || fail "Cannot write to PX4-Autopilot; investigate WSL storage/I/O errors."
grep -qx "drone-slam-write-test" "$write_test" 2>/dev/null || fail "PX4 repository write/read test failed."
rm -f "$write_test"

px4_rootfs="$HOME/PX4-Autopilot/build/px4_sitl_default/rootfs"
[[ -d "$px4_rootfs" ]] || fail "PX4 SITL rootfs is missing: $px4_rootfs"
mkdir -p "$px4_rootfs/log" 2>/dev/null || fail "Cannot create/access PX4 SITL log directory: $px4_rootfs/log"
for dir in "$px4_rootfs" "$px4_rootfs/log"; do
  write_test="$dir/.drone_slam_write_test"
  printf "drone-slam-write-test\n" > "$write_test" 2>/dev/null || fail "Cannot write inside $dir; prior logger/DataManager errors may persist."
  grep -qx "drone-slam-write-test" "$write_test" 2>/dev/null || fail "PX4 SITL write/read test failed inside $dir."
  rm -f "$write_test"
done
ok "PX4 repository, SITL rootfs, and log directory pass write/read tests."

existing="$(pgrep -af '[p]x4_sitl_default|[m]ake px4_sitl gz_x500_mono_cam_walls|[g]z sim.*walls|[o]rbslam3_node|[p]arameter_bridge.*world/walls/model/x500_mono_cam_0|[r]ecord_gt.py' || true)"
if [[ -n "$existing" ]]; then
  echo "$existing"
  fail "Old Drone-SLAM processes are still running after the stop step."
fi
ok "No duplicate Drone-SLAM processes found."

# ROS setup scripts use environment variables that may intentionally be unset.
# Temporarily disable nounset while sourcing the ROS and workspace overlays.
set +u
if ! source /opt/ros/humble/setup.bash; then
  set -u
  fail "Could not source ROS 2 Humble."
fi
if ! source "$HOME/px4_ros2_ws/install/setup.bash"; then
  set -u
  fail "Could not source the px4_ros2_ws overlay."
fi
set -u

orb_executables="$(ros2 pkg executables orbslam3_ros 2>/dev/null || true)"
grep -Eq '(^|[[:space:]])orbslam3_node

ip4_details="$(ip -4 addr show eth0 2>/dev/null || true)"
wsl_ip="$(awk '/inet / {split($2,a,"/"); print a[1]; exit}' <<< "$ip4_details")"
if [[ -n "$wsl_ip" ]]; then
  echo
  echo "Current WSL eth0 IP: $wsl_ip"
  echo "QGroundControl's saved UDP link should target this IP on port 18570."
fi

echo
echo "PRECHECK PASSED. No vehicle arming or movement was commanded."
 <<< "$orb_executables" || fail "ROS executable orbslam3_ros/orbslam3_node is not installed in the workspace."
ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1 || fail "ROS package ros_gz_bridge is not available."
ok "ROS 2 Humble, ros_gz_bridge, and orbslam3_node are available."

ip4_details="$(ip -4 addr show eth0 2>/dev/null || true)"
wsl_ip="$(awk '/inet / {split($2,a,"/"); print a[1]; exit}' <<< "$ip4_details")"
if [[ -n "$wsl_ip" ]]; then
  echo
  echo "Current WSL eth0 IP: $wsl_ip"
  echo "QGroundControl's saved UDP link should target this IP on port 18570."
fi

echo
echo "PRECHECK PASSED. No vehicle arming or movement was commanded."
