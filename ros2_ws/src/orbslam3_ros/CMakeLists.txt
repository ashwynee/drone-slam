cmake_minimum_required(VERSION 3.8)
project(orbslam3_ros)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_TYPE Release)

# ORB-SLAM3 installation
set(ORB_SLAM3_ROOT "$ENV{HOME}/ORB_SLAM3")

# ROS 2 dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(OpenCV REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(OpenGL REQUIRED)
find_package(GLEW REQUIRED)

# ORB-SLAM3 library
set(ORB_SLAM3_LIBRARY "${ORB_SLAM3_ROOT}/lib/libORB_SLAM3.so")

if(NOT EXISTS "${ORB_SLAM3_LIBRARY}")
  message(FATAL_ERROR
    "ORB-SLAM3 library not found: ${ORB_SLAM3_LIBRARY}"
  )
endif()

# Pangolin library
find_library(
  PANGOLIN_LIBRARY
  NAMES pangolin
  PATHS /usr/local/lib /usr/lib
  REQUIRED
)

# ROS 2 executable
add_executable(
  orbslam3_node
  src/orbslam3_node.cpp
)

# Header files
target_include_directories(
  orbslam3_node
  PRIVATE
    "${ORB_SLAM3_ROOT}"
    "${ORB_SLAM3_ROOT}/include"
    "${ORB_SLAM3_ROOT}/include/CameraModels"
    "${ORB_SLAM3_ROOT}/Thirdparty/DBoW2"
    "${ORB_SLAM3_ROOT}/Thirdparty/DBoW2/DBoW2"
    "${ORB_SLAM3_ROOT}/Thirdparty/g2o"
    "${ORB_SLAM3_ROOT}/Thirdparty/Sophus"
    /usr/local/include
    ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(
  orbslam3_node
  "${ORB_SLAM3_LIBRARY}"
  "${PANGOLIN_LIBRARY}"
  ${OpenCV_LIBS}
  Eigen3::Eigen
  GL
  OpenGL::GL
  GLEW::GLEW
)

ament_target_dependencies(
  orbslam3_node
  rclcpp
  sensor_msgs
  cv_bridge
)

# Find ORB-SLAM3's shared library when launching the node
set_target_properties(
  orbslam3_node
  PROPERTIES
    BUILD_RPATH "${ORB_SLAM3_ROOT}/lib;/usr/local/lib"
    INSTALL_RPATH "${ORB_SLAM3_ROOT}/lib;/usr/local/lib"
)

install(
  TARGETS orbslam3_node
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
