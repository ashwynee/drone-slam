# Live Drone-SLAM Simulation

A simulation-based monocular visual SLAM prototype integrating **PX4 SITL**, **Gazebo**, **ROS 2 Humble**, and **ORB-SLAM3**. This repository includes earlier offline RGB-D and EuRoC experiments plus the live simulation integration and evaluation.

## Live simulation architecture

```text
PX4 SITL + Gazebo (walls world, x500_mono_cam)
                    |
                    v
           Gazebo camera image
                    |
                    v
             ros_gz_bridge
                    |
                    v
             ROS 2 image topic
                    |
                    v
               ORB-SLAM3
             /           \
      sparse map       camera poses
                           |
                           +---- Gazebo ground-truth poses
                                      |
                                      v
                             trajectory evaluation
```

## Live simulation: observed results

The live camera stream delivered **320×240 images at approximately 4.6–5 Hz**. ORB-SLAM3 reached tracking state **2** and was observed tracking hundreds of map points, including during a controlled Gazebo movement of approximately **1.06 m horizontally**. A timestamped, model-filtered Gazebo ground-truth recorder was implemented and verified.

A preliminary similarity-aligned evaluation on the recorded live run produced:

| Metric | Preliminary result |
|---|---:|
| SLAM input rows | 3,176 |
| Ground-truth input rows | 24,755 |
| Timestamp-matched SLAM poses | 2,360 |
| Overlap | 428.4–900.8 s |
| Estimated monocular scale | 4.334112 m / map unit |
| Aligned ATE RMSE | 0.314582 m |
| Aligned ATE median | 0.146724 m |
| Aligned ATE maximum | 1.208540 m |
| Ground-truth path length | 21.309730 m |
| Aligned SLAM path length | 36.338119 m |
| Ground-truth net displacement | 3.136216 m |

**Interpretation and limitations:** the plotted trajectories diverge and the error plot includes spikes. The similarity transform and scale were estimated using the same trajectory being evaluated, so these numbers are *preliminary aligned errors*, not an independent accuracy benchmark. SLAM estimates the camera pose while Gazebo ground truth is the drone model pose; camera-to-body extrinsics also affect comparisons. Robustness and drift still need improvement.

### Live trajectory comparison

![Gazebo ground truth vs aligned and scale-corrected ORB-SLAM3 trajectory](results/live_gazebo/live_trajectory_comparison.png)

### Live position error

![Preliminary aligned position error over Gazebo simulation time](results/live_gazebo/live_trajectory_error.png)

Full metric report: [live_evaluation_metrics.txt](results/live_gazebo/live_evaluation_metrics.txt).

## Offline benchmark results (separate from live simulation)

### TUM RGB-D — freiburg1_desk

| Metric | Result |
|---|---:|
| Estimated / matched poses | 573 |
| Match coverage | 100% |
| ATE RMSE | 0.0231 m |
| ATE median | 0.0173 m |
| ATE maximum | 0.0667 m |

These values apply to a separate offline RGB-D experiment and **must not be presented as live monocular Gazebo accuracy**.

### EuRoC MAV — MH_01_easy

The repository also contains a preliminary ORB-SLAM3 Stereo-Inertial evaluation of EuRoC `MH_01_easy` (ATE RMSE 0.0660 m, median 0.0547 m, maximum 0.1458 m). Initialization continuity and coordinate-frame conventions still require validation.

Existing offline visualizations:
- [TUM trajectory comparison](results/trajectory_comparison.png)
- [TUM position error](results/trajectory_error.png)
- [EuRoC trajectory comparison](results/euroc_mh01/trajectory_comparison.png)
- [EuRoC position error](results/euroc_mh01/trajectory_error.png)

## Environment and project paths

- Ubuntu 22.04 under WSL2
- ROS 2 Humble
- PX4 repository: `~/PX4-Autopilot`
- Gazebo world: `~/PX4-Autopilot/Tools/simulation/gz/worlds/walls.sdf`
- Drone model: `~/PX4-Autopilot/Tools/simulation/gz/models/x500_mono_cam/model.sdf`
- ROS workspace: `~/px4_ros2_ws`
- ORB-SLAM3: `~/ORB_SLAM3`
- Config: `~/ORB_SLAM3/Examples/Monocular/Drone320.yaml`
- Results: `~/drone-slam/results/live_gazebo/`

## Run the live simulation

Use separate terminals. Verify spawn position and preflight status on each run. Never bypass PX4 safety checks.

### Terminal 1 — PX4 + Gazebo

```bash
cd ~/PX4-Autopilot
PX4_SIM_SPEED_FACTOR=1 make px4_sitl gz_x500_mono_cam_walls
```

At `pxh>` run `commander check` and verify the spawned model is near the feature wall.

### Terminal 2 — ROS 2 camera bridge

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
'/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image@sensor_msgs/msg/Image[gz.msgs.Image' \
'/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'
```

### Terminal 3 — ORB-SLAM3 node

```bash
source /opt/ros/humble/setup.bash
cd ~/px4_ros2_ws
source install/setup.bash
export LD_LIBRARY_PATH="$HOME/ORB_SLAM3/lib:$LD_LIBRARY_PATH"
ros2 run orbslam3_ros orbslam3_node --ros-args \
-r '/world/default/model/x500_mono_cam_down_0/link/camera_link/sensor/camera/image:=/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image'
```

### Terminal 4 — filtered Gazebo ground truth

The helper `scripts/record_gt.py` records only model `x500_mono_cam_0` from `/world/walls/dynamic_pose/info` in TUM format. Stop it with Ctrl+C after the test. Before isolated runs, stop ORB-SLAM3 cleanly and archive prior logs because the SLAM logger opens its trajectory in append mode.

```bash
python3 ~/drone-slam/scripts/record_gt.py \
  ~/drone-slam/results/live_gazebo/ground_truth.txt
```

The evaluator `scripts/evaluate_live.py` creates the live plots, aligned CSV and metrics report.

## Repository contents

- `ros2_ws/src/orbslam3_ros/` — ROS 2 ORB-SLAM3 node and build files
- `config/Drone320.yaml` — camera settings
- `scripts/` — association and trajectory evaluation utilities
- `results/` — offline benchmark results and live simulation outputs

## Known limitations and next work

1. Improve initialization and recovery when the camera's view changes substantially.
2. Validate live results on a held-out movement segment after estimating scale/alignment on a separate segment.
3. Apply the camera-to-body extrinsic transform before comparing camera poses with drone model poses.
4. Investigate drift and the error spikes in the current live trajectory evaluation.
5. Current milestone is **simulation only**; physical phone/IMU visual-inertial integration is outside scope.

## Attribution

ORB-SLAM3, the TUM RGB-D dataset, EuRoC MAV dataset, and dependencies retain their respective licenses and attribution requirements. See upstream documentation before redistributing third-party assets.


### One-click Windows launcher

For WSL2 on Windows, `scripts/launch_demo.bat` attempts to open QGroundControl (GCS) from the Windows Start Menu or common install paths, then opens separate windows for PX4/Gazebo, the camera bridge, the ground-truth recorder, and ORB-SLAM3. QGroundControl detection and connection to PX4 must be verified on the local machine; if it is not found, launch it manually from the Windows Start menu. The launcher archives previous trajectory/evaluation outputs before preparing a fresh run. It does **not** arm or move the drone automatically. Preflight and movement remain manual safety-controlled actions.

To install the launcher on the Windows Desktop from the WSL Ubuntu terminal:

```bash
mkdir -p ~/drone-slam/scripts
curl -fL https://raw.githubusercontent.com/ashwynee/drone-slam/main/scripts/prepare_demo_run.sh -o ~/drone-slam/scripts/prepare_demo_run.sh
curl -fL https://raw.githubusercontent.com/ashwynee/drone-slam/main/scripts/launch_demo.bat -o ~/drone-slam/scripts/launch_demo.bat
chmod +x ~/drone-slam/scripts/prepare_demo_run.sh
WIN_DESKTOP="$(powershell.exe -NoProfile -Command '[Environment]::GetFolderPath("Desktop")' | tr -d '\r')"
cp ~/drone-slam/scripts/launch_demo.bat "$(wslpath "$WIN_DESKTOP")/Drone-SLAM Demo.bat"
```

The existing local `scripts/record_gt.py` recorder is still required in `~/drone-slam/scripts/`. Keep that file in place. First test the launcher while observing the terminal windows; WSL, Gazebo startup time, or a changed local setup may require adjusting its delays.
