#!/usr/bin/env bash
set -Eeuo pipefail
readonly PREPARE_RUN_VERSION="2026-10-29.8"

RESULTS="$HOME/drone-slam/results/live_gazebo"
mkdir -p "$RESULTS/archive"
STAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE="$RESULTS/archive/run_$STAMP"
mkdir -p "$ARCHIVE"

# Archive prior artifacts before resetting the live-run files.
for file in LiveCameraTrajectory.txt ground_truth.txt live_trajectory_comparison.png live_trajectory_error.png live_aligned_trajectory.csv live_evaluation_metrics.txt px4_console.log; do
  if [[ -f "$RESULTS/$file" ]]; then
    cp -a "$RESULTS/$file" "$ARCHIVE/"
  fi
done

: > "$RESULTS/LiveCameraTrajectory.txt"
: > "$RESULTS/ground_truth.txt"
# Critical: remove the previous run's readiness marker before the health gate begins.
: > "$RESULTS/px4_console.log"
printf 'prepared_at=%s\n' "$(date --iso-8601=seconds)" > "$RESULTS/current_run.txt"

echo "Previous result files preserved in: $ARCHIVE"
echo "New trajectory files prepared."
echo "Fresh PX4 console log prepared; previous Ready-for-takeoff markers cannot be reused."
