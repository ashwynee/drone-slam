# Drone-SLAM Project Checkpoint

## Current scope
Simulation-only monocular SLAM using PX4 SITL, Gazebo, ROS 2 Humble, and ORB-SLAM3.

## Verified in live runs
- PX4/Gazebo `walls` world launched and passed `commander check`.
- Fresh drone spawn at the world origin was verified.
- ROS 2 camera bridge created image and CameraInfo bridges.
- Camera images arrived at 320×240 and approximately 4.6–5 Hz.
- ORB-SLAM3 reached tracking state 2 with hundreds to 1,000+ tracked map points.
- Live trajectory logger appended TUM-format camera-to-world poses while tracking state 2.
- Filtered Gazebo ground-truth recorder captured only `x500_mono_cam_0` at around 45–53 Hz in observed tests.
- A controlled movement produced approximately 1.06 m of horizontal Gazebo displacement while ORB-SLAM3 continued tracking.
- Preliminary live trajectory plots and aligned error metrics were generated.

## Preliminary live evaluation
- Matched SLAM poses: 2,360
- Aligned ATE RMSE: 0.314582 m
- Median aligned error: 0.146724 m
- Maximum aligned error: 1.208540 m
- Estimated scale: 4.334112 m per SLAM map unit

These are preliminary because alignment and scale were fitted on the same trajectory segment. Plots show drift and error spikes; the numbers are not an independent accuracy benchmark.

## Separate offline RGB-D benchmark
TUM RGB-D freiburg1_desk: ATE RMSE 0.0231 m across 573 matched poses. This is not the live monocular Gazebo result.

## Remaining limitations
- Tracking may fail during large viewpoint changes or low visual overlap.
- Monocular scale and coordinate frame must be estimated.
- Compare camera pose to Gazebo drone-body pose only after applying the camera-to-body extrinsics.
- A held-out trajectory segment should be used for a more defensible accuracy estimate.
