# Drone SLAM - Checkpoint

## Architecture
PX4 SITL + Gazebo Sim -> ros_gz_bridge -> ROS 2 -> ORB-SLAM3.

## Verified
- Gazebo ArUco world server runs and simulation clock advances.
- Gazebo camera topic exists:
  /world/aruco/model/x500_mono_cam_down_0/link/camera_link/sensor/camera/image
- ROS 2 receives bridged camera images at approximately 5 FPS.
- ORB-SLAM3 ROS 2 package builds and receives 320x240 frames.
- PX4 preflight check reported OK.
- QGroundControl connected to PX4.

## Not yet working / unresolved
- ORB-SLAM3 tracking state remains 1 (NOT_INITIALIZED).
- QGroundControl previously displayed an accelerometer sensor timeout warning.
- Live drone movement and successful SLAM initialization are not verified.

## Camera configuration
See config/Drone320.yaml.

## Important
Do not claim successful live SLAM until tracking state reaches 2.
Keep PX4, Gazebo, ROS 2 bridge and ORB-SLAM3 setup instructions documented.
