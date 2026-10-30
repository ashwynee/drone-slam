#include <cstdlib>
#include <functional>
#include <memory>
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
        const std::string vocab = std::string(std::getenv("HOME")) +
            "/ORB_SLAM3/Vocabulary/ORBvoc.txt";
        const std::string settings = std::string(std::getenv("HOME")) +
            "/ORB_SLAM3/Examples/Monocular/Drone320.yaml";

        slam_ = std::make_unique<ORB_SLAM3::System>(
            vocab, settings, ORB_SLAM3::System::MONOCULAR, false);

        const auto image_topic =
            declare_parameter<std::string>("image_topic", "/camera/image");

        subscription_ = create_subscription<sensor_msgs::msg::Image>(
            image_topic, rclcpp::SensorDataQoS(),
            std::bind(&ORBSLAM3Node::image_callback, this,
                      std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "ORB-SLAM3 subscribing to: %s",
                    image_topic.c_str());
    }

    ~ORBSLAM3Node() override
    {
        if (slam_) slam_->Shutdown();
    }

private:
    void image_callback(const sensor_msgs::msg::Image::ConstSharedPtr msg)
    {
        RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 2000,
            "Received frame: %ux%u (%s)",
            msg->width, msg->height, msg->encoding.c_str());
        try {
            cv::Mat image = cv_bridge::toCvCopy(msg, "bgr8")->image;
            const double timestamp =
                rclcpp::Time(msg->header.stamp).seconds();
            slam_->TrackMonocular(image, timestamp);
            RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 2000,
                "Tracking state: %d, tracked map points: %zu",
                slam_->GetTrackingState(),
                slam_->GetTrackedMapPoints().size());
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
