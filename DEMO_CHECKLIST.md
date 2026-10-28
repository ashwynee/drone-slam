# Drone-SLAM Demo Checklist (Simulation Only)

## Before demo
- [ ] Start PX4/Gazebo using the documented `walls` world command.
- [ ] Check the vehicle spawn position near the visual landmark wall.
- [ ] Confirm `commander check` passes; never bypass preflight checks.
- [ ] Start ROS 2 bridge and verify 320×240 camera frames.
- [ ] Start ORB-SLAM3 and show tracking state 2 with map points.
- [ ] If running live, start filtered ground-truth recording before the controlled movement.
- [ ] Keep the movement short; stop if tracking is lost or the vehicle behaves unexpectedly.
- [ ] Land and save trajectories.
- [ ] Open `results/live_gazebo/live_trajectory_comparison.png` and `live_trajectory_error.png`.
- [ ] Show `results/live_gazebo/live_evaluation_metrics.txt`.

## Two-minute presentation

“This project integrates PX4 SITL, Gazebo, ROS 2, and ORB-SLAM3 for live monocular visual SLAM in simulation. The simulated camera feed is bridged into ROS 2, where ORB-SLAM3 tracks visual features, creates a sparse map, and logs camera poses. Gazebo's drone pose is recorded separately as ground truth.

“In the live test, camera images were 320 by 240, and ORB-SLAM3 reached tracking state 2 with hundreds of tracked map points. During a controlled movement, Gazebo recorded approximately 1.06 metres of horizontal displacement while the SLAM tracker continued running. We generated trajectory comparison and error plots from the recorded run.

“The preliminary similarity-aligned evaluation reports an ATE RMSE of about 0.315 metres, median error of about 0.147 metres, and maximum error of about 1.209 metres. The current plots show drift and error spikes. These metrics are preliminary because scale and alignment were estimated from the same trajectory. Improving drift, camera-to-body calibration, and independent validation are next steps.”

## Accuracy caveats
- Do not report the offline RGB-D ATE RMSE of 0.0231 m as the live monocular result.
- Live aligned ATE RMSE 0.314582 m is preliminary, not an independent accuracy benchmark.
- State clearly that this milestone is simulation-only.
