@echo off
setlocal EnableExtensions
title Drone-SLAM One-Click Demo
set "FAIL_STAGE=starting"
echo.
echo ============================================================
echo              DRONE-SLAM ONE-CLICK DEMO
echo ============================================================
echo.
echo This launcher will stop old Drone-SLAM PX4/Gazebo/ROS
echo processes only. It will NOT arm or move the vehicle.
echo Previous trajectory results will be archived, not deleted.
echo.
choice /C YN /N /M "Continue with a clean restart of the Drone-SLAM demo? [Y/N] "
if errorlevel 2 goto cancelled

set "FAIL_STAGE=updating launcher helper scripts"
echo.
echo [1/7] Updating Linux helper scripts from GitHub...
wsl.exe -e bash -lc "set -euo pipefail; mkdir -p ~/drone-slam/scripts; for f in prepare_demo_run.sh preflight_demo.sh stop_demo.sh wait_for_px4_ready.sh run_px4_gz.sh wait_for_gz_camera.sh wait_for_ros_camera.sh wait_for_ground_truth.sh verify_orbslam_process.sh; do curl -fsSL --retry 2 --connect-timeout 10 https://raw.githubusercontent.com/ashwynee/drone-slam/main/scripts/$f -o ~/drone-slam/scripts/$f.tmp || exit 1; mv ~/drone-slam/scripts/$f.tmp ~/drone-slam/scripts/$f || exit 1; done; chmod +x ~/drone-slam/scripts/*.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=stopping old demo processes"
echo.
echo [2/7] Stopping old Drone-SLAM processes...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/stop_demo.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=preflight checks"
echo.
echo [3/7] Checking storage, filesystem writes, project files, and ROS packages...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/preflight_demo.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=archiving prior results"
echo.
echo Archiving prior results and preparing clean trajectory files...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/prepare_demo_run.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=launching QGroundControl"
echo.
echo [4/7] Opening QGroundControl (or leaving it open if already running)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; if (Get-Process -Name QGroundControl -ErrorAction SilentlyContinue) { Write-Host 'QGroundControl is already running.'; exit 0 }; $roots=@($env:ProgramData+'\Microsoft\Windows\Start Menu\Programs',$env:APPDATA+'\Microsoft\Windows\Start Menu\Programs'); $lnk=Get-ChildItem $roots -Filter 'QGroundControl.lnk' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if($lnk) { Start-Process $lnk.FullName; exit 0 }; $pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'); $paths=@(($env:ProgramFiles+'\QGroundControl\QGroundControl.exe'),($pf86+'\QGroundControl\QGroundControl.exe'),($env:LOCALAPPDATA+'\Programs\QGroundControl\QGroundControl.exe')); $exe=$paths | Where-Object { Test-Path $_ } | Select-Object -First 1; if($exe) { Start-Process $exe; exit 0 }; Write-Error 'QGroundControl was not found'; exit 1"
if errorlevel 1 (
  echo QGroundControl could not be launched automatically.
  echo Open QGroundControl from the Windows Start menu, then return here.
  pause
  powershell.exe -NoProfile -Command "if (Get-Process -Name QGroundControl -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
  if errorlevel 1 goto failed
)
timeout /t 15 /nobreak >nul
powershell.exe -NoProfile -Command "if (Get-Process -Name QGroundControl -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if errorlevel 1 (
  echo QGroundControl did not stay open.
  echo Open it from the Windows Start menu and try the launcher again.
  goto failed
)
echo [OK] QGroundControl process is open.
echo Confirm its saved WSL UDP link points to the current IP shown in the preflight output, port 18570.

set "FAIL_STAGE=starting PX4/Gazebo"
echo.
echo [5/7] Starting PX4 + Gazebo in its own window...
start "PX4 + Gazebo" wsl.exe -e bash -lc "bash ~/drone-slam/scripts/run_px4_gz.sh"
set "FAIL_STAGE=waiting for PX4 readiness, GCS, and sensor/storage health"
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/wait_for_px4_ready.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=waiting for the Gazebo camera topic"
echo Waiting for the actual Gazebo camera topic (up to 180 seconds)...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/wait_for_gz_camera.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=starting or verifying ROS camera bridge"
echo.
echo [6/7] Starting the camera bridge...
start "ROS 2 Camera Bridge" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash; ros2 run ros_gz_bridge parameter_bridge '/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image@sensor_msgs/msg/Image[gz.msgs.Image' '/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'; rc=$?; echo; echo 'ROS 2 bridge exited with code' $rc; read -r -p 'Bridge stopped. Press Enter to close...' _"
echo Waiting for real ROS camera messages (up to 90 seconds)...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/wait_for_ros_camera.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=starting or verifying ground-truth recorder"
echo.
echo Starting the ground-truth recorder...
start "Ground Truth Recorder" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash; python3 ~/drone-slam/scripts/record_gt.py; rc=$?; echo; echo 'Ground-truth recorder exited with code' $rc; read -r -p 'Recorder stopped. Press Enter to close...' _"
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/wait_for_ground_truth.sh"
if errorlevel 1 goto failed

set "FAIL_STAGE=starting or verifying ORB-SLAM3"
echo.
echo [7/7] Starting ORB-SLAM3...
start "ORB-SLAM3" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash; cd ~/px4_ros2_ws && source install/setup.bash && export LD_LIBRARY_PATH=$HOME/ORB_SLAM3/lib:$LD_LIBRARY_PATH && ros2 run orbslam3_ros orbslam3_node --ros-args -r '/world/default/model/x500_mono_cam_down_0/link/camera_link/sensor/camera/image:=/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image'; rc=$?; echo; echo 'ORB-SLAM3 exited with code' $rc; read -r -p 'ORB-SLAM3 stopped. Press Enter to close...' _"
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/verify_orbslam_process.sh"
if errorlevel 1 goto failed

echo.
echo ============================================================
echo STARTUP CHECKS PASSED
echo ============================================================
echo QGroundControl process is open.
echo Gazebo camera topic was detected.
echo ROS camera messages were received.
echo Ground-truth output was verified.
echo ORB-SLAM3 node process is running.
echo.
echo IMPORTANT:
echo - This verifies process/data startup; it does NOT prove SLAM is initialized.
echo - A stationary camera produces no parallax; ORB-SLAM3 may remain in state 1.
echo - The prior run showed accelerometer timeouts and logger/dataman I/O errors.
echo - Do NOT arm or move unless QGC is connected and PX4 preflight/sensor status is clean.
echo - If the GCS warning returns, verify the saved QGC WSL IP matches the preflight IP on UDP 18570.
echo.
pause
exit /b 0

:cancelled
echo Launcher cancelled; no processes were changed.
pause
exit /b 0

:failed
echo.
echo ============================================================
echo LAUNCHER STOPPED AT: %FAIL_STAGE%
echo ============================================================
echo It intentionally stopped at the failed check instead of
echo starting later components and pretending the demo works.
echo Read the error just above this message and the related
echo component window. Previous results were archived, not deleted.
echo.
pause
exit /b 1
