#!/usr/bin/env bash
# Version marker confirms the launcher downloaded the current helper from GitHub.
# Do not enable nounset in this script: ROS 2 setup files may reference unset vars.
set -Ee -o pipefail

readonly PRECHECK_VERSION="2026-10-29.8"
fail() { echo; echo "PRECHECK FAILED: $*" >&2; exit 1; }
ok() { echo "[OK] $*"; }

echo "=== Drone-SLAM preflight v$PRECHECK_VERSION ==="
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
grep -qx drone-slam-write-test "$test_file" || fail "PX4 repository write/read test failed."
rm -f "$test_file"

px4_rootfs="$HOME/PX4-Autopilot/build/px4_sitl_default/rootfs"
[[ -d "$px4_rootfs" ]] || fail "PX4 SITL rootfs is missing: $px4_rootfs"
mkdir -p "$px4_rootfs/log" 2>/dev/null || fail "Cannot access PX4 SITL log directory."
for dir in "$px4_rootfs" "$px4_rootfs/log"; do
  test_file="$dir/.drone_slam_write_test"
  printf 'drone-slam-write-test\n' > "$test_file" 2>/dev/null || fail "Cannot write in $dir; previous PX4 I/O errors may persist."
  grep -qx drone-slam-write-test "$test_file" || fail "Write/read test failed in $dir."
  rm -f "$test_file"
done
ok "PX4 repository, SITL rootfs, and log directory pass write/read tests."

existing="$(ps -eo pid=,comm=,args= | awk '
  {
    pid=$1; comm=$2; args=$0
    sub(/^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", args)
    if (comm == "px4") print pid " " comm " " args
    else if (comm == "make" && args ~ /^make px4_sitl gz_x500_mono_cam_walls([[:space:]]|$)/) print pid " " comm " " args
    else if (comm == "gz" && args ~ /^gz sim .*\/worlds\/walls\.sdf([[:space:]]|$)/) print pid " " comm " " args
    else if (comm == "orbslam3_node") print pid " " comm " " args
    else if (comm == "ros2" && args ~ /^ros2 run ros_gz_bridge parameter_bridge .*world\/walls\/model\/x500_mono_cam_0/) print pid " " comm " " args
    else if ((comm == "python3" || comm == "python") && args ~ /\/drone-slam\/scripts\/record_gt\.py([[:space:]]|$)/) print pid " " comm " " args
  }
' || true)"
if [[ -n "$existing" ]]; then
  echo "$existing"
  fail "Old Drone-SLAM processes remain after the stop step."
fi
ok "No duplicate Drone-SLAM processes found."

# Catch malformed helper downloads before the launcher starts PX4.
for script in prepare_demo_run.sh preflight_demo.sh stop_demo.sh wait_for_px4_ready.sh run_px4_gz.sh wait_for_gz_camera.sh wait_for_ros_camera.sh wait_for_ground_truth.sh verify_orbslam_process.sh; do
  bash -n "$HOME/drone-slam/scripts/$script" || fail "Shell syntax check failed for $HOME/drone-slam/scripts/$script."
done
ok "All downloaded Linux launcher helpers pass bash -n syntax checks."

# Isolate ROS setup from inherited shell options and profile files. nounset must be off.
if env -u SHELLOPTS bash --noprofile --norc -c '
  set +u
  source /opt/ros/humble/setup.bash || exit 21
  source "$HOME/px4_ros2_ws/install/setup.bash" || exit 22
  ros2 pkg prefix ros_gz_bridge >/dev/null 2>&1 || exit 23
  ros2 pkg executables orbslam3_ros | grep -F orbslam3_node >/dev/null || exit 24
'; then
  ok "ROS 2 Humble, ros_gz_bridge, and orbslam3_node are available."
else
  fail "ROS setup or required ROS package/executable check failed. The nested shell disables inherited SHELLOPTS and nounset."
fi

ip4_details="$(ip -4 addr show eth0 2>/dev/null || true)"
wsl_ip="$(awk '/inet / {split($2,a,"/"); print a[1]; exit}' <<< "$ip4_details")"
if [[ -n "$wsl_ip" ]]; then
  echo
  echo "Current WSL eth0 IP: $wsl_ip"
  echo "QGroundControl's saved UDP link should target this IP on port 18570."
fi

echo
echo "PRECHECK PASSED. No vehicle arming or movement was commanded."
