#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <memory>
#include <stdexcept>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "cv_bridge/cv_bridge.h"
#include <opencv2/opencv.hpp>
#include "System.h"

class ORBSLAM3Node : public rclcpp::Node
{
public:
    ORBSLAM3Node() : Node("orbslam3_node")
    {
        const char *home = std::getenv("HOME");
        if (home == nullptr) {
            throw std::runtime_error("HOME environment variable is not set");
        }

        const std::string vocab =
            std::string(home) + "/ORB_SLAM3/Vocabulary/ORBvoc.txt";
        const std::string settings =
            std::string(home) + "/ORB_SLAM3/Examples/Monocular/Drone320.yaml";

        const auto trajectory_file = declare_parameter<std::string>(
            "trajectory_file",
            std::string(home) +
                "/drone-slam/results/live_gazebo/LiveCameraTrajectory.txt");

        const std::filesystem::path trajectory_path(trajectory_file);
        if (!trajectory_path.parent_path().empty()) {
            std::filesystem::create_directories(trajectory_path.parent_path());
        }

        trajectory_stream_.open(
            trajectory_path, std::ios::out | std::ios::trunc);
        if (!trajectory_stream_.is_open()) {
            throw std::runtime_error(
                "Could not open trajectory output: " + trajectory_file);
        }

        trajectory_stream_ << std::fixed;
        RCLCPP_INFO(
            get_logger(), "Writing tracked camera poses to: %s",
            trajectory_file.c_str());

        slam_ = std::make_unique<ORB_SLAM3::System>(
            vocab, settings, ORB_SLAM3::System::MONOCULAR, false);

        const auto image_topic =
            declare_parameter<std::string>("image_topic", "/camera/image");

        subscription_ = create_subscription<sensor_msgs::msg::Image>(
            image_topic, rclcpp::SensorDataQoS(),
            std::bind(&ORBSLAM3Node::image_callback, this,
                      std::placeholders::_1));

        RCLCPP_INFO(
            get_logger(), "ORB-SLAM3 subscribing to: %s",
            image_topic.c_str());
    }

    ~ORBSLAM3Node() override
    {
        if (slam_) {
            slam_->Shutdown();
        }
        if (trajectory_stream_.is_open()) {
            trajectory_stream_.flush();
            trajectory_stream_.close();
        }
    }

private:
    void image_callback(const sensor_msgs::msg::Image::ConstSharedPtr msg)
    {
        RCLCPP_INFO_THROTTLE(
            get_logger(), *get_clock(), 2000,
            "Received frame: %ux%u (%s)",
            msg->width, msg->height, msg->encoding.c_str());

        try {
            const cv::Mat image =
                cv_bridge::toCvCopy(msg, "bgr8")->image;
            const double timestamp =
                rclcpp::Time(msg->header.stamp).seconds();

            const Sophus::SE3f Tcw = slam_->TrackMonocular(image, timestamp);
            const int state = slam_->GetTrackingState();
            const auto tracked_points = slam_->GetTrackedMapPoints().size();

            if (state == 2) {
                // ORB-SLAM3 returns world-to-camera (Tcw); save camera-to-world (Twc).
                const Sophus::SE3f Twc = Tcw.inverse();
                const Eigen::Vector3f position = Twc.translation();
                const Eigen::Quaternionf orientation = Twc.unit_quaternion();

                trajectory_stream_
                    << std::setprecision(6) << timestamp << " "
                    << std::setprecision(7)
                    << position.x() << " "
                    << position.y() << " "
                    << position.z() << " "
                    << orientation.x() << " "
                    << orientation.y() << " "
                    << orientation.z() << " "
                    << orientation.w() << "\n";
                trajectory_stream_.flush();
            }

            RCLCPP_INFO_THROTTLE(
                get_logger(), *get_clock(), 2000,
                "Tracking state: %d, tracked map points: %zu; saved poses: %lld",
                state, tracked_points,
                static_cast<long long>(saved_pose_count_));
            if (state == 2) {
                ++saved_pose_count_;
            }
        } catch (const std::exception &e) {
            RCLCPP_ERROR(
                get_logger(), "Image processing failed: %s", e.what());
        }
    }

    std::unique_ptr<ORB_SLAM3::System> slam_;
    rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr subscription_;
    std::ofstream trajectory_stream_;
    long long saved_pose_count_{0};
};

int main(int argc, char **argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ORBSLAM3Node>());
    rclcpp::shutdown();
    return 0;
}
