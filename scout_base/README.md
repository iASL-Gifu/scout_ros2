# Scout Base

## Note

* In the scout_wheel_type1.xacro and scout_wheel_type2.xacro models, the type of wheel joint is set to be "continuous" instead of "fixed" since joint state publisher is not implemented for scout yet

## Joystick control

`scout_joy_controller` converts `sensor_msgs/msg/Joy` messages on `/joy` to
`geometry_msgs/msg/Twist` commands on `/cmd_vel`.

The default mapping is defined in `config/scout_joy_controller.yaml`:

* Axis 1: linear velocity
* Axis 0: angular velocity
* Button 3: deadman/manual button; hold it while driving
* Button 5: increase the speed limit by 10%
* Button 4: decrease the speed limit by 10%

Start the Scout Mini base, joystick driver, and joystick controller together:

```bash
ros2 launch scout_base scout_mini_joy_control.launch.py
```

Axis/button numbers and velocity limits can be changed in the YAML file. A
different parameter file can also be selected at launch time:

```bash
ros2 launch scout_base scout_mini_joy_control.launch.py \
  config_file:=/path/to/scout_joy_controller.yaml
```

The joystick device can be changed with `joy_device_id` (`0` selects
`/dev/input/js0`):

```bash
ros2 launch scout_base scout_mini_joy_control.launch.py joy_device_id:=1
```

`normalizer` is an input gain applied to each joystick axis before it is
limited to the range -1.0 to 1.0.

The controller publishes a zero velocity when the manual button is released or
when joystick messages stop for longer than `joy_timeout` (0.5 seconds by
default).
