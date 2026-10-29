#!/usr/bin/env bash
# Do not enable nounset here: ROS 2 setup scripts reference optional unset vars.
set -Ee -o pipefail

fail() { echo; echo "PRECHECK FAILED: $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

echo "=== Drone-SLAM preflight ==="
echo "Checking required files, storage, filesystem writes, ROS packages, and duplicate processes."
echo

required_paths=(
  "$HOME/PX4-Autopilot/Tools/simulation/gz/worlds/walls.sdf"
  "$HOME/PX4-Autopilot/Tools/simulation/gz/models/x500_mono_cam/model.sdf"
  "$HOME/px4_ros2_ws/install/setup.bash"
  "$HOME/ORB_SLAM3/lib/libORB_SLAM3.so"
  "$HOME/ORB_SLAM3/Vocabulary/ORBvoc.txt"
  "$HOME/ORB_SLAM3/Examples/Monocular/Drone320.yaml"
  "$HOME/drone-slam/scripts/record_gt.py"
)
for path in "${required_paths[@]}"; do
  [[ -r "$path" ]] || fail "Required file missing or unreadable: $path"
done
ok "Required project files and the local ground-truth recorder exist."

command -v gz >/dev/null 2>&1 || fail "Gazebo CLI 'gz' not found in PATH."
command -v timeout >/dev/null 2>&1 || fail "GNU timeout is not available."
command -v curl >/dev/null 2>&1 || fail "curl is not available."
command -v pgrep >/dev/null 2>&1 || fail "pgrep is not available."
ok "Gazebo CLI and required system tools are available."

home_free="$(df -Pm "$HOME" | awk 'NR==2 {print $4}')"
[[ "$home_free" =~ ^[0-9]+$ ]] || fail "Could not read available WSL storage."
if (( home_free < 4096 )); then
  fail "Only $home_free MB free on the WSL filesystem; at least 4096 MB is required."
fi
ok "WSL filesystem has $home_free MB available."

if [[ -d /mnt/c ]]; then
  c_free="$(df -Pm /mnt/c | awk 'NR==2 {print $4}')"
  [[ "$c_free" =~ ^[0-9]+$ ]] || fail "Could not read free space on Windows C:."
  if (( c_free < 4096 )); then
    fail "Only $c_free MB free on Windows C:. Free at least 4096 MB before launching."
  fi
  ok "Windows C: has $c_free MB available."
fi

for path in "$HOME/PX4-Autopilot" "$HOME/px4_ros2_ws" "$HOME/drone-slam"; do
  [[ -w "$path" ]] || fail "Project directory is not writable: $path"
done

test_file="$HOME/PX4-Autopilot/.drone_slam_write_test"
printf 'drone-slam-write-test\n' > "$test_file" 2>/dev/null || fail "Cannot write to PX4-Autopilot."
grep -qx 'drone-slam-write-test' "$test_file" || fail "PX4 repository write/read test failed."
rm -f "$test_file"

px4_rootfs="$HOME/PX4-Autopilot/build/px4_sitl_default/rootfs"
[[ -d "$px4_rootfs" ]] || fail "PX4 SITL rootfs is missing: $px4_rootfs"
mkdir -p "$px4_rootfs/log" 2>/dev/null || fail "Cannot access PX4 SITL log directory."
for dir in "$px4_rootfs" "$px4_rootfs/log"; do
  test_file="$dir/.drone_slam_write_test"
  printf 'drone-slam-write-test\n' > "$test_file" 2>/dev/null || fail "Cannot write in $dir; previous PX4 I/O errors may persist."
  grep -qx 'drone-slam-write-test' "$test_file" || fail "Write/read test failed in $dir."
  rm -f "$test_file"
done
ok "PX4 repository, SITL rootfs, and log directory pass write/read tests."

existing="$(pgrep -af '[p]x4_sitl_default|[m]ake px4_sitl gz_x500_mono_cam_walls|[g]z sim.*walls|[o]rbslam3_node|[p]arameter_bridge.*world/walls/model/x500_mono_cam_0|[r]ecord_gt.py' || true)"
if [[ -n "$existing" ]]; then
  echo "$existing"
  fail "Old Drone-SLAM processes remain after the stop step."
fi
ok "No duplicate Drone-SLAM processes found."

# ROS setup files expect optional variables to be unset; leave nounset disabled.
source /opt/ros/humble/setup.bash || fail "Could not source ROS 2 Humble."
source "$HOME/px4_ros2_ws/install/setup.bash" || fail "Could not source the ROS workspace overlay."

orb_executables="$(ros2 pkg executables orbslam3_ros 2>/dev/null || true)"
if ! awk '$NF == "orbslam3_node" { found=1 } END { exit !found }' <<< "$orb_executables"; then
  fail "ROS executable orbslam3_ros/orbslam3_node is not installed in the workspace."
fi
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
