#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>

#include <geometry_msgs/msg/twist.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/joy.hpp>

class ScoutJoyController : public rclcpp::Node
{
public:
  ScoutJoyController()
  : Node("scout_joy_controller")
  {
    joy_topic_ = declare_parameter<std::string>("joy_topic", "/joy");
    cmd_vel_topic_ = declare_parameter<std::string>("cmd_vel_topic", "/cmd_vel");

    min_speed_ = declare_parameter<double>("min_speed", 0.0);
    max_speed_ = declare_parameter<double>("max_speed", 1.6666);
    min_angle_ = declare_parameter<double>("min_angle", -0.5);
    max_angle_ = declare_parameter<double>("max_angle", 0.5);
    normalizer_ = declare_parameter<double>("normalizer", 2.0);
    manual_button_ = declare_parameter<int>("manual_button", 3);
    speed_plus_button_ = declare_parameter<int>("speed_plus_button", 5);
    speed_minus_button_ = declare_parameter<int>("speed_minus_button", 4);
    speed_axes_ = declare_parameter<int>("speed_axes", 1);
    angle_axes_ = declare_parameter<int>("angle_axes", 0);

    speed_limit_step_ = declare_parameter<double>("speed_limit_step", 0.1);
    speed_limit_factor_ = declare_parameter<double>("initial_speed_limit_factor", 1.0);
    joy_timeout_ = declare_parameter<double>("joy_timeout", 0.5);

    speed_limit_factor_ = std::max(0.0, std::min(1.0, speed_limit_factor_));

    if (speed_axes_ < 0 || angle_axes_ < 0 || manual_button_ < 0 ||
      speed_plus_button_ < 0 || speed_minus_button_ < 0)
    {
      throw std::invalid_argument("Joystick axis and button indices must be non-negative");
    }
    if (min_speed_ < 0.0 || max_speed_ < min_speed_ || min_angle_ > 0.0 ||
      max_angle_ < 0.0 || normalizer_ <= 0.0 || speed_limit_step_ <= 0.0 || joy_timeout_ <= 0.0)
    {
      throw std::invalid_argument(
              "Invalid speed, angle, normalizer, speed_limit_step, or joy_timeout parameter");
    }

    cmd_vel_pub_ = create_publisher<geometry_msgs::msg::Twist>(cmd_vel_topic_, 5);
    joy_sub_ = create_subscription<sensor_msgs::msg::Joy>(
      joy_topic_, rclcpp::SensorDataQoS(),
      std::bind(&ScoutJoyController::joy_callback, this, std::placeholders::_1));

    watchdog_timer_ = create_wall_timer(
      std::chrono::milliseconds(100),
      std::bind(&ScoutJoyController::watchdog_callback, this));

    RCLCPP_INFO(
      get_logger(),
      "Listening on %s and publishing to %s (linear axis: %d, angular axis: %d, "
      "manual button: %d)",
      joy_topic_.c_str(), cmd_vel_topic_.c_str(), speed_axes_, angle_axes_, manual_button_);
  }

private:
  bool has_axis(const sensor_msgs::msg::Joy & msg, int index) const
  {
    return static_cast<std::size_t>(index) < msg.axes.size();
  }

  bool has_button(const sensor_msgs::msg::Joy & msg, int index) const
  {
    return static_cast<std::size_t>(index) < msg.buttons.size();
  }

  bool button_pressed(const sensor_msgs::msg::Joy & msg, int index) const
  {
    return has_button(msg, index) && msg.buttons[static_cast<std::size_t>(index)] != 0;
  }

  void publish_stop()
  {
    cmd_vel_pub_->publish(geometry_msgs::msg::Twist());
  }

  void joy_callback(const sensor_msgs::msg::Joy::SharedPtr msg)
  {
    last_joy_time_ = now();
    received_joy_ = true;

    if (!has_axis(*msg, speed_axes_) || !has_axis(*msg, angle_axes_) ||
      !has_button(*msg, manual_button_) || !has_button(*msg, speed_plus_button_) ||
      !has_button(*msg, speed_minus_button_))
    {
      RCLCPP_WARN_THROTTLE(
        get_logger(), *get_clock(), 5000,
        "Joy message does not contain all configured axes/buttons; publishing stop command");
      if (manual_active_) {
        publish_stop();
      }
      manual_active_ = false;
      return;
    }

    const bool plus_pressed = button_pressed(*msg, speed_plus_button_);
    const bool minus_pressed = button_pressed(*msg, speed_minus_button_);

    if (plus_pressed && !previous_plus_pressed_) {
      speed_limit_factor_ = std::min(1.0, speed_limit_factor_ + speed_limit_step_);
      RCLCPP_INFO(get_logger(), "Speed limit: %.0f%%", speed_limit_factor_ * 100.0);
    }
    if (minus_pressed && !previous_minus_pressed_) {
      speed_limit_factor_ = std::max(0.0, speed_limit_factor_ - speed_limit_step_);
      RCLCPP_INFO(get_logger(), "Speed limit: %.0f%%", speed_limit_factor_ * 100.0);
    }
    previous_plus_pressed_ = plus_pressed;
    previous_minus_pressed_ = minus_pressed;

    const bool manual_pressed = button_pressed(*msg, manual_button_);
    if (!manual_pressed) {
      if (manual_active_) {
        publish_stop();
      }
      manual_active_ = false;
      return;
    }

    const double speed_input = std::max(
      -1.0, std::min(
        1.0, static_cast<double>(msg->axes[static_cast<std::size_t>(speed_axes_)]) * normalizer_));
    const double angle_input = std::max(
      -1.0, std::min(
        1.0, static_cast<double>(msg->axes[static_cast<std::size_t>(angle_axes_)]) * normalizer_));

    double linear_speed = 0.0;
    if (speed_input != 0.0) {
      const double speed_magnitude =
        min_speed_ + std::abs(speed_input) * (max_speed_ - min_speed_);
      linear_speed = speed_input > 0.0 ? speed_magnitude : -speed_magnitude;
    }

    const double angular_speed = angle_input >= 0.0 ?
      angle_input * max_angle_ : -angle_input * min_angle_;

    geometry_msgs::msg::Twist command;
    command.linear.x = linear_speed * speed_limit_factor_;
    command.angular.z = angular_speed * speed_limit_factor_;
    cmd_vel_pub_->publish(command);
    manual_active_ = true;
  }

  void watchdog_callback()
  {
    if (!received_joy_ || !manual_active_) {
      return;
    }

    if ((now() - last_joy_time_).seconds() > joy_timeout_) {
      publish_stop();
      manual_active_ = false;
      RCLCPP_WARN(get_logger(), "Joy input timed out; publishing stop command");
    }
  }

  std::string joy_topic_;
  std::string cmd_vel_topic_;
  double min_speed_;
  double max_speed_;
  double min_angle_;
  double max_angle_;
  double normalizer_;
  int manual_button_;
  int speed_plus_button_;
  int speed_minus_button_;
  int speed_axes_;
  int angle_axes_;
  double speed_limit_step_;
  double speed_limit_factor_;
  double joy_timeout_;

  bool previous_plus_pressed_{false};
  bool previous_minus_pressed_{false};
  bool manual_active_{false};
  bool received_joy_{false};
  rclcpp::Time last_joy_time_{0, 0, RCL_ROS_TIME};

  rclcpp::Subscription<sensor_msgs::msg::Joy>::SharedPtr joy_sub_;
  rclcpp::Publisher<geometry_msgs::msg::Twist>::SharedPtr cmd_vel_pub_;
  rclcpp::TimerBase::SharedPtr watchdog_timer_;
};

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<ScoutJoyController>());
  rclcpp::shutdown();
  return 0;
}
