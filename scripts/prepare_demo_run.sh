#!/usr/bin/env bash
set -euo pipefail

RESULTS="$HOME/drone-slam/results/live_gazebo"
mkdir -p "$RESULTS/archive"
STAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE="$RESULTS/archive/run_$STAMP"
mkdir -p "$ARCHIVE"

for file in LiveCameraTrajectory.txt ground_truth.txt live_trajectory_comparison.png live_trajectory_error.png live_aligned_trajectory.csv live_evaluation_metrics.txt px4_console.log; do
  if [[ -f "$RESULTS/$file" ]]; then
    cp -a "$RESULTS/$file" "$ARCHIVE/"
  fi
done

: > "$RESULTS/LiveCameraTrajectory.txt"
: > "$RESULTS/ground_truth.txt"
echo "Previous result files preserved in: $ARCHIVE"
echo "New trajectory files prepared."
