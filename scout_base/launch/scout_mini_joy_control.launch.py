from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    default_controller_config = PathJoinSubstitution([
        FindPackageShare('scout_base'),
        'config',
        'scout_joy_controller.yaml',
    ])

    config_file_arg = DeclareLaunchArgument(
        'config_file',
        default_value=default_controller_config,
        description='Path to the Scout joystick controller parameter file',
    )
    joy_device_id_arg = DeclareLaunchArgument(
        'joy_device_id',
        default_value='0',
        description='Joystick device ID (/dev/input/js0 is 0)',
    )
    joy_deadzone_arg = DeclareLaunchArgument(
        'joy_deadzone',
        default_value='0.05',
        description='Joystick deadzone',
    )
    joy_autorepeat_rate_arg = DeclareLaunchArgument(
        'joy_autorepeat_rate',
        default_value='20.0',
        description='Rate at which unchanged Joy messages are republished [Hz]',
    )

    scout_mini_base = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('scout_base'),
                'launch',
                'scout_mini_base.launch.py',
            ])
        )
    )

    joy_node = Node(
        package='joy',
        executable='joy_node',
        name='joy_node',
        output='screen',
        parameters=[{
            'device_id': ParameterValue(LaunchConfiguration('joy_device_id'), value_type=int),
            'deadzone': ParameterValue(LaunchConfiguration('joy_deadzone'), value_type=float),
            'autorepeat_rate': ParameterValue(
                LaunchConfiguration('joy_autorepeat_rate'), value_type=float
            ),
        }],
    )

    joy_controller = Node(
        package='scout_base',
        executable='scout_joy_controller',
        name='scout_joy_controller',
        output='screen',
        parameters=[LaunchConfiguration('config_file')],
    )

    return LaunchDescription([
        config_file_arg,
        joy_device_id_arg,
        joy_deadzone_arg,
        joy_autorepeat_rate_arg,
        scout_mini_base,
        joy_node,
        joy_controller,
    ])
