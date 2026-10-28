@echo off
setlocal
title Drone-SLAM One-Click Demo

echo.
echo Preparing a fresh run and archiving previous results...
wsl.exe -e bash -lc "bash ~/drone-slam/scripts/prepare_demo_run.sh"
if errorlevel 1 (
  echo ERROR: Could not prepare results. Check that ~/drone-slam is updated in WSL.
  pause
  exit /b 1
)

echo Launching QGroundControl (GCS), if installed...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$roots=@($env:ProgramData+'\Microsoft\Windows\Start Menu\Programs',$env:APPDATA+'\Microsoft\Windows\Start Menu\Programs'); $lnk=Get-ChildItem $roots -Filter 'QGroundControl.lnk' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if($lnk){Start-Process $lnk.FullName; exit 0}; $paths=@($env:ProgramFiles+'\QGroundControl\QGroundControl.exe', ${env:ProgramFiles(x86)}+'\QGroundControl\QGroundControl.exe', $env:LOCALAPPDATA+'\Programs\QGroundControl\QGroundControl.exe'); $exe=$paths | Where-Object { Test-Path $_ } | Select-Object -First 1; if($exe){Start-Process $exe} else {Write-Host 'QGroundControl shortcut/executable not found. Open QGroundControl from the Windows Start menu manually.'}"

echo Starting PX4 + Gazebo...
start "PX4 + Gazebo" wsl.exe -e bash -lc "cd ~/PX4-Autopilot && PX4_SIM_SPEED_FACTOR=1 make px4_sitl gz_x500_mono_cam_walls; code=$?; echo; echo 'PX4/Gazebo process exited with code' $code; read -r -p 'Press Enter to close this window...' _"

echo Waiting 20 seconds for Gazebo...
timeout /t 20 /nobreak >nul

echo Starting ROS-Gazebo camera bridge...
start "ROS 2 Camera Bridge" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash && ros2 run ros_gz_bridge parameter_bridge '/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image@sensor_msgs/msg/Image[gz.msgs.Image' '/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'; code=$?; echo; echo 'ROS 2 bridge exited with code' $code; read -r -p 'Press Enter to close this window...' _"

timeout /t 5 /nobreak >nul
echo Starting Gazebo ground-truth recorder...
start "Ground Truth Recorder" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash && python3 ~/drone-slam/scripts/record_gt.py; code=$?; echo; echo 'Ground-truth recorder exited with code' $code; read -r -p 'Press Enter to close this window...' _"

timeout /t 5 /nobreak >nul
echo Starting ORB-SLAM3...
start "ORB-SLAM3" wsl.exe -e bash -lc "source /opt/ros/humble/setup.bash && cd ~/px4_ros2_ws && source install/setup.bash && export LD_LIBRARY_PATH=$HOME/ORB_SLAM3/lib:$LD_LIBRARY_PATH && ros2 run orbslam3_ros orbslam3_node --ros-args -r '/world/default/model/x500_mono_cam_down_0/link/camera_link/sensor/camera/image:=/world/walls/model/x500_mono_cam_0/link/camera_link/sensor/camera/image'; code=$?; echo; echo 'ORB-SLAM3 exited with code' $code; read -r -p 'Press Enter to close this window...' _"

echo.
echo Launcher started. Verify the four new terminal windows stay open and show no errors.
echo This does not arm or move the drone automatically.
timeout /t 8 /nobreak >nul
