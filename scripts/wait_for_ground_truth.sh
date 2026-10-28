#!/usr/bin/env bash
set -Eeuo pipefail
file="$HOME/drone-slam/results/live_gazebo/ground_truth.txt"
echo "Waiting up to 20 seconds for ground-truth recorder output..."
for ((i=1; i<=20; i++)); do
  if [[ -s "$file" ]]; then
    lines="$(wc -l < "$file")"
    if [[ "$lines" =~ ^[0-9]+$ ]] && (( lines >= 2 )); then
      echo "[OK] Ground-truth recorder wrote $lines rows to $file"
      exit 0
    fi
  fi
  sleep 1
done
echo "ERROR: Ground-truth file did not receive at least two rows within 20 seconds." >&2
echo "Check the Ground Truth Recorder window; the launcher will not claim recording is active." >&2
exit 1
