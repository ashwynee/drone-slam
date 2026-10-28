#!/usr/bin/env bash
set -uo pipefail

PX4_DIR="$HOME/PX4-Autopilot"
LOG="$HOME/drone-slam/results/live_gazebo/px4_console.log"
mkdir -p "$(dirname "$LOG")"
cd "$PX4_DIR" || { echo "ERROR: PX4-Autopilot directory not found: $PX4_DIR"; read -r -p "Press Enter to close..." _; exit 1; }

: > "$LOG" || { echo "ERROR: Cannot create PX4 console log at $LOG"; read -r -p "Press Enter to close..." _; exit 1; }
echo "PX4/Gazebo console output is also being saved to: $LOG"
echo "Starting PX4 SITL + Gazebo walls world. No arming or movement is commanded."
PX4_SIM_SPEED_FACTOR=1 make px4_sitl gz_x500_mono_cam_walls 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
echo
echo "PX4/Gazebo exited with code $rc"
read -r -p "PX4/Gazebo stopped. Press Enter to close this window..." _
exit "$rc"
