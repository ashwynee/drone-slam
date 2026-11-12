#!/usr/bin/env python3
import sys
import subprocess
import signal

output_path = sys.argv[1] if len(sys.argv) > 1 else "/home/aswini/drone-slam/results/live_gazebo/ground_truth.txt"

print(f"[GT-RECORDER] Recording x500_mono_cam_0 pose to: {output_path}")
print("[GT-RECORDER] Press Ctrl+C to stop recording.")

cmd = ["gz", "topic", "-e", "-t", "/world/walls/dynamic_pose/info"]
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)

def handle_sigint(sig, frame):
    proc.terminate()
    sys.exit(0)

signal.signal(signal.SIGINT, handle_sigint)

current_sim_time = None
in_drone = False
pos = {}
ori = {}

with open(output_path, "w") as f:
    for line in proc.stdout:
        line_s = line.strip()

        # Capture timestamp from header
        if line_s.startswith("sec:") and "nsec:" not in line_s:
            parts = line_s.split(":")
            sec = int(parts[1].strip())
        elif line_s.startswith("nsec:"):
            parts = line_s.split(":")
            nsec = int(parts[1].strip())
            current_sim_time = sec + nsec * 1e-9

        # Target block
        if line_s == 'name: "x500_mono_cam_0"':
            in_drone = True
            pos = {}
            ori = {}
            continue

        if in_drone:
            if line_s.startswith("x:") and 'x' not in pos:
                pos['x'] = line_s.split(":")[1].strip()
            elif line_s.startswith("y:") and 'y' not in pos:
                pos['y'] = line_s.split(":")[1].strip()
            elif line_s.startswith("z:") and 'z' not in pos:
                pos['z'] = line_s.split(":")[1].strip()
            elif line_s.startswith("x:") and 'x' in pos and 'x' not in ori:
                ori['x'] = line_s.split(":")[1].strip()
            elif line_s.startswith("y:") and 'y' in pos and 'y' not in ori:
                ori['y'] = line_s.split(":")[1].strip()
            elif line_s.startswith("z:") and 'z' in pos and 'z' not in ori:
                ori['z'] = line_s.split(":")[1].strip()
            elif line_s.startswith("w:"):
                ori['w'] = line_s.split(":")[1].strip()
                in_drone = False
                
                # Write TUM format line: timestamp tx ty tz qx qy qz qw
                if current_sim_time is not None and len(pos) == 3 and len(ori) == 4:
                    f.write(f"{current_sim_time:.6f} {pos['x']} {pos['y']} {pos['z']} {ori['x']} {ori['y']} {ori['z']} {ori['w']}\n")
                    f.flush()
