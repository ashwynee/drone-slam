# Visual SLAM and Drone Navigation

A computer vision and robotics project exploring Simultaneous
Localization and Mapping (SLAM) using ORB-SLAM3, RGB-D sensor data,
trajectory evaluation, and drone simulation tools.

## Project Overview

This project uses recorded RGB-D data to estimate camera motion,
reconstruct a trajectory, and evaluate localization accuracy against
ground-truth poses.

The initial experiment uses the TUM RGB-D benchmark. The next phase
will extend the workflow to visual-inertial drone datasets and
PX4/Gazebo simulation.

## Technology Stack

- C++
- Python 3
- ORB-SLAM3
- OpenCV
- Eigen
- Pangolin
- NumPy
- Matplotlib
- Ubuntu 22.04
- ROS 2 Humble
- PX4 and Gazebo (planned integration)

## Dataset

TUM RGB-D benchmark: freiburg1_desk

Dataset source:
https://cvg.cit.tum.de/rgbd/dataset/freiburg1

The sequence contains RGB images, depth images, timestamps, and
ground-truth camera poses.

The dataset is used for offline RGB-D SLAM evaluation. This experiment
does not yet perform visual-inertial drone navigation.

## Implementation

1. Prepare the recorded RGB and depth image sequences.
2. Associate RGB and depth frames using timestamps.
3. Run ORB-SLAM3 in RGB-D mode.
4. Export estimated camera and keyframe trajectories.
5. Match estimated poses with ground-truth timestamps.
6. Align trajectories using rigid rotation and translation.
7. Calculate Absolute Trajectory Error (ATE).
8. Visualize the trajectory and position error.

## Preliminary Results

The initial local evaluation reported:

- Estimated camera poses: 596
- ATE RMSE: approximately 0.017 m
- Equivalent RMSE: approximately 1.7 cm

These are preliminary results from the local evaluation script.
The matched-pose count, timestamp tolerance, alignment method, and
evaluation implementation should be verified before treating the
number as a final benchmark result.

## Output Files

- results/CameraTrajectory.txt
- results/KeyFrameTrajectory.txt
- results/trajectory_comparison.png
- results/trajectory_error.png
- results/baseline/

The baseline directory preserves copies of the initial trajectories
and visualizations.

## Project Structure

drone-slam/
├── data/
├── results/
│   └── baseline/
├── scripts/
│   ├── associate.py
│   └── evaluate_trajectory.py
├── .venv/
└── README.md

Dataset files and the Python virtual environment should remain local
rather than being committed to Git.

## Reproducibility

Python environment:

    python3 -m venv .venv
    source .venv/bin/activate
    python -m pip install "numpy==1.26.4" "matplotlib==3.8.4" pandas pyyaml opencv-python

Generate RGB-depth associations:

    python scripts/associate.py

Evaluate the saved trajectory:

    python scripts/evaluate_trajectory.py

The ORB-SLAM3 executable and vocabulary must be built and available
at the paths configured in the local run instructions.

## Roadmap

- [x] Set up the Python environment.
- [x] Build ORB-SLAM3 and its dependencies.
- [x] Run an RGB-D sequence.
- [x] Export camera and keyframe trajectories.
- [x] Generate trajectory comparison and error plots.
- [x] Preserve baseline outputs.
- [ ] Validate the evaluation against an independent implementation.
- [ ] Evaluate additional benchmark sequences.
- [ ] Run visual-inertial SLAM on a drone-specific dataset.
- [ ] Integrate PX4 and Gazebo simulation.
- [ ] Compare simulated drone trajectories with ground truth.

## Future Work

The long-term goal is a drone navigation workflow combining camera
and IMU measurements, visual-inertial localization, mapping, and
simulation-based evaluation.

## License and Attribution

ORB-SLAM3 and the dataset retain their original licenses and
attribution requirements. Refer to their official sources before
redistributing code or data.
