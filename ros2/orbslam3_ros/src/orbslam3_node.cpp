
#include <memory>
#include <string>
#include <chrono>

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
        const std::string vocab =
            std::string(std::getenv("HOME")) +
            "/ORB_SLAM3/Vocabulary/ORBvoc.txt";

        const std::string settings =
            std::string(std::getenv("HOME")) +
            "/ORB_SLAM3/Examples/Monocular/TUM1.yaml";

        slam_ = std::make_unique<ORB_SLAM3::System>(
            vocab, settings, ORB_SLAM3::System::MONOCULAR, true);

        subscription_ = create_subscription<sensor_msgs::msg::Image>(
            "/world/default/model/x500_mono_cam_down_0/link/camera_link/sensor/camera/image",
            rclcpp::SensorDataQoS(),
            std::bind(&ORBSLAM3Node::image_callback, this,
                      std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "ORB-SLAM3 ROS 2 node started.");
    }

    ~ORBSLAM3Node() override
    {
        if (slam_) {
            slam_->Shutdown();
        }
    }

private:
    void image_callback(const sensor_msgs::msg::Image::ConstSharedPtr msg)
    {
        try {
            cv::Mat image =
                cv_bridge::toCvCopy(msg, "bgr8")->image;

            const double timestamp =
                rclcpp::Time(msg->header.stamp).seconds();

            slam_->TrackMonocular(image, timestamp);
        } catch (const std::exception &e) {
            RCLCPP_ERROR(get_logger(), "Image processing failed: %s", e.what());
        }
    }

    std::unique_ptr<ORB_SLAM3::System> slam_;
    rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr subscription_;
};

int main(int argc, char **argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ORBSLAM3Node>());
    rclcpp::shutdown();
    return 0;
}
