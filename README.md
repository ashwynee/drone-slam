# Drone-SLAM: PX4, Gazebo, ROS 2 and ORB-SLAM3

Simulation-only monocular visual SLAM prototype. The current development stack is PX4 SITL, Gazebo, ROS 2 Humble, and ORB-SLAM3.

## Architecture

```text
PX4 SITL + Gazebo camera
        |
        v
Gazebo Transport image topic
        |
        v
ros_gz_bridge
        |
        v
ROS 2 sensor_msgs/Image
        |
        v
ORB-SLAM3 monocular tracking
        |
        +---- sparse map and camera trajectory
        |
Gazebo model ground truth
        |
        v
trajectory association and evaluation
```

## Current verified capabilities

- Gazebo camera images were previously received at 320x240 and approximately 5 Hz.
- ORB-SLAM3 reached tracking state 2 and tracked hundreds of map points during a controlled simulation movement.
- Camera poses were logged in TUM trajectory format.
- A model-filtered Gazebo ground-truth recorder and live trajectory evaluator were used.
- The current live accuracy evaluation is still under investigation. Do not treat similarity-aligned ATE as independent accuracy because scale and alignment were fitted using the trajectory being evaluated.
- The current build target is simulation only. Physical drone flight and phone/IMU visual-inertial integration are not part of this milestone.

## Environment and paths

- Ubuntu 22.04 under WSL2
- ROS 2 Humble
- PX4: `~/PX4-Autopilot`
- ROS 2 overlay workspace: `~/px4_ros2_ws`
- ORB-SLAM3: `~/ORB_SLAM3`
- Monocular settings: `~/ORB_SLAM3/Examples/Monocular/Drone320.yaml`
- Repository: `~/drone-slam`
- Live output: `~/drone-slam/results/live_gazebo/`
- Main ROS node source in this repository: `ros2_ws/src/orbslam3_ros/src/orbslam3_node.cpp`

## Manual run workflow

Use separate Ubuntu terminals. Do not run an arming command or bypass PX4 preflight checks. First confirm the simulation world and vehicle spawn successfully.

### Terminal 1 — PX4 SITL + Gazebo

```bash
cd ~/PX4-Autopilot
PX4_SIM_SPEED_FACTOR=1 make px4_sitl gz_x500_mono_cam_walls
```

Wait for Gazebo and PX4 startup. At the `pxh>` prompt, use the PX4 status/preflight checks and confirm there are no sensor, estimator, or logger failures before controlled simulation movement.

### Terminal 2 — discover the Gazebo camera topic

Do not assume a world or model name. Discover the image topic from the running simulation:

```bash
gz topic -l | grep -Ei 'camera.*/image|/image$'
```

Copy the exact image topic printed. Inspect its type and whether messages are being published:

```bash
gz topic -i -t 'PASTE_EXACT_GAZEBO_IMAGE_TOPIC'
gz topic -e -t 'PASTE_EXACT_GAZEBO_IMAGE_TOPIC' --duration 3
```

Stop the echo with Ctrl+C. This is the Gazebo Transport topic, before bridging.

### Terminal 3 — ROS 2 camera bridge

```bash
source /opt/ros/humble/setup.bash
ros2 run ros_gz_bridge parameter_bridge \
  'PASTE_EXACT_GAZEBO_IMAGE_TOPIC@sensor_msgs/msg/Image[gz.msgs.Image'
```

Use the exact Gazebo topic discovered in Terminal 2. If CameraInfo is needed, discover its exact Gazebo topic separately and bridge it as `sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo`.

### Terminal 4 — verify the bridged ROS image topic

```bash
source /opt/ros/humble/setup.bash
ros2 topic list -t | grep -Ei 'camera|image'
```

Then inspect the exact ROS image topic shown:

```bash
ros2 topic info -v 'PASTE_EXACT_ROS_IMAGE_TOPIC'
ros2 topic hz 'PASTE_EXACT_ROS_IMAGE_TOPIC'
```

The expected message type is `sensor_msgs/msg/Image`. Let `ros2 topic hz` run for several samples and stop it with Ctrl+C. Do not launch ORB-SLAM3 until the topic has a publisher and a nonzero rate.

### Terminal 5 — ORB-SLAM3 ROS 2 node

Build the package after source changes:

```bash
source /opt/ros/humble/setup.bash
cd ~/px4_ros2_ws
colcon build --packages-select orbslam3_ros --symlink-install
source install/setup.bash
export LD_LIBRARY_PATH="$HOME/ORB_SLAM3/lib:$LD_LIBRARY_PATH"
```

Launch using the exact ROS image topic discovered in Terminal 4. The node's `image_topic` parameter is intended to make the input topic configurable:

```bash
ros2 run orbslam3_ros orbslam3_node --ros-args \
  -p image_topic:='PASTE_EXACT_ROS_IMAGE_TOPIC'
```

Confirm that the node logs the selected topic, received image dimensions, tracking state, and tracked map-point count. Tracking state 2 indicates successful tracking; a running process alone does not prove SLAM has initialized.

### Terminal 6 — ground-truth recording

The local helper `~/drone-slam/scripts/record_gt.py` records the selected Gazebo model in TUM format. Confirm its world topic and model filter match the current simulation before recording.

```bash
python3 ~/drone-slam/scripts/record_gt.py \
  ~/drone-slam/results/live_gazebo/ground_truth.txt
```

Stop with Ctrl+C after the movement test. Make sure recording begins before moving the simulated vehicle.

## Evaluate the live run

The local evaluator `~/drone-slam/scripts/evaluate_live.py` writes the aligned trajectory CSV, trajectory comparison plot, and error plot.

Use the project virtual environment to avoid mixing system NumPy and Matplotlib installations:

```bash
cd ~/drone-slam
source .venv/bin/activate
python scripts/evaluate_live.py
```

Interpretation caveats:
- Monocular SLAM has unknown scale; a fitted similarity transform is an alignment diagnostic, not independent metric-scale validation.
- The ORB-SLAM3 output is the camera trajectory. Gazebo ground truth recorded for the drone model is a body/model trajectory; apply measured camera-to-body extrinsics before treating them as directly comparable.
- Stationary periods should not dominate movement accuracy summaries.
- Use a separate alignment/calibration segment and held-out evaluation segment for a defensible accuracy result.

## Camera configuration

The current monocular configuration is `Drone320.yaml`:
- Resolution: 320 x 240
- Configured frame rate: 5 FPS
- ORB feature target: 1,000

The configured FPS does not guarantee the live ROS stream rate. Measure the actual topic rate with `ros2 topic hz`. Improve the camera resolution/frame rate only after confirming the bridge and tracking pipeline are stable.

## Offline results are separate

The repository contains earlier offline TUM RGB-D and EuRoC experiments. Their metrics are not live monocular Gazebo results and must not be used to describe live simulation accuracy.

## Repository layout

- `ros2_ws/src/orbslam3_ros/` — ROS 2 ORB-SLAM3 node
- `config/` — camera configuration copy
- `scripts/` — evaluation and association scripts; some live-run helpers remain local only
- `results/` — recorded plots, CSVs and benchmark outputs

## Next engineering priorities

1. Make the live camera topic configurable and verify topic discovery/bridge data end to end.
2. Increase and measure image rate/resolution without destabilizing the WSL/Gazebo pipeline.
3. Fix startup tracking transients and investigate trajectory jumps.
4. Estimate camera-to-body extrinsics and correct timestamp/frame conventions.
5. Evaluate on held-out moving segments, report ATE/RPE, and only then add mapping-based obstacle avoidance.

## Attribution

ORB-SLAM3, PX4, Gazebo, ROS 2, TUM RGB-D, EuRoC MAV and third-party dependencies retain their respective licenses and attribution requirements.
