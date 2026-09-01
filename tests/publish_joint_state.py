"""Publish a bounded synthetic BPX pose for the Docker-only TF smoke test."""

from __future__ import annotations


JOINT_NAMES = (
    "fl_hip_roll_joint",
    "fl_hip_pitch_joint",
    "fl_knee_joint",
    "fr_hip_roll_joint",
    "fr_hip_pitch_joint",
    "fr_knee_joint",
    "hl_hip_roll_joint",
    "hl_hip_pitch_joint",
    "hl_knee_joint",
    "hr_hip_roll_joint",
    "hr_hip_pitch_joint",
    "hr_knee_joint",
)
JOINT_POSITIONS = (
    0.0,
    0.5,
    -1.0,
    0.0,
    0.5,
    -1.0,
    0.0,
    0.5,
    -1.0,
    0.0,
    0.5,
    -1.0,
)


def main() -> None:
    import rclpy
    from rclpy.node import Node
    from sensor_msgs.msg import JointState

    rclpy.init()
    node = Node("mirrorme_bpx_tf_fixture")
    publisher = node.create_publisher(JointState, "/joint_states", 10)

    def publish() -> None:
        message = JointState()
        message.header.stamp = node.get_clock().now().to_msg()
        message.name = list(JOINT_NAMES)
        message.position = list(JOINT_POSITIONS)
        publisher.publish(message)

    node.create_timer(0.1, publish)
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
