from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
VENDOR_URDF = ROOT / "description/bpx/urdf/bpx.urdf"
DEPLOYMENT_URDF = ROOT / "urdf/mirrorme_bpx.urdf"
GENERATOR = ROOT / "scripts/generate_deployment_urdf.py"
JOINT_STATE_PUBLISHER = ROOT / "tests/publish_joint_state.py"
VENDOR_SHA256 = "9432a00fdd3f27ab1c756a529c8ed74f41f6b810fd3977caebc577ad38ffdc9e"


def load_generator():
    spec = importlib.util.spec_from_file_location("deployment_urdf_generator", GENERATOR)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DeploymentUrdfTest(unittest.TestCase):
    def test_vendor_urdf_remains_byte_exact(self) -> None:
        digest = hashlib.sha256(VENDOR_URDF.read_bytes()).hexdigest()
        self.assertEqual(VENDOR_SHA256, digest)

    def test_generated_urdf_matches_the_deterministic_renderer(self) -> None:
        generator = load_generator()
        expected = generator.render(VENDOR_URDF.read_text(encoding="utf-8"))
        self.assertEqual(expected, DEPLOYMENT_URDF.read_text(encoding="utf-8"))

    def test_base_link_is_the_identity_parent_of_vendor_torso(self) -> None:
        root = ET.parse(DEPLOYMENT_URDF).getroot()
        links = {element.attrib["name"] for element in root.findall("link")}
        joints = {element.attrib["name"]: element for element in root.findall("joint")}

        self.assertEqual("mirrorme_bpx", root.attrib["name"])
        self.assertEqual(18, len(links))
        self.assertEqual(17, len(joints))
        self.assertIn("base_link", links)
        self.assertIn("torso", links)

        alias = joints["base_link_to_torso"]
        self.assertEqual("fixed", alias.attrib["type"])
        self.assertEqual("base_link", alias.find("parent").attrib["link"])
        self.assertEqual("torso", alias.find("child").attrib["link"])
        self.assertEqual("0 0 0", alias.find("origin").attrib["xyz"])
        self.assertEqual("0 0 0", alias.find("origin").attrib["rpy"])

        child_links = {
            joint.find("child").attrib["link"] for joint in joints.values()
        }
        self.assertNotIn("base_link", child_links)
        self.assertIn("torso", child_links)

    def test_every_deployment_mesh_reference_resolves_inside_repository(self) -> None:
        root = ET.parse(DEPLOYMENT_URDF).getroot()
        repository = ROOT.resolve()
        meshes = root.findall(".//mesh")
        self.assertGreater(len(meshes), 0)
        for mesh in meshes:
            resolved = (DEPLOYMENT_URDF.parent / mesh.attrib["filename"]).resolve()
            self.assertIn(repository, resolved.parents)
            self.assertTrue(resolved.is_file(), resolved)

    def test_synthetic_tf_pose_covers_all_revolute_joints_within_limits(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "joint_state_fixture", JOINT_STATE_PUBLISHER
        )
        assert spec is not None and spec.loader is not None
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)

        root = ET.parse(DEPLOYMENT_URDF).getroot()
        limits = {}
        for joint in root.findall("joint"):
            if joint.attrib["type"] != "revolute":
                continue
            limit = joint.find("limit")
            limits[joint.attrib["name"]] = (
                float(limit.attrib["lower"]),
                float(limit.attrib["upper"]),
            )

        self.assertEqual(set(limits), set(fixture.JOINT_NAMES))
        self.assertEqual(len(fixture.JOINT_NAMES), len(fixture.JOINT_POSITIONS))
        for name, position in zip(fixture.JOINT_NAMES, fixture.JOINT_POSITIONS):
            lower, upper = limits[name]
            self.assertLessEqual(lower, position, name)
            self.assertLessEqual(position, upper, name)


class ShellWrapperTest(unittest.TestCase):
    def test_tf_smoke_sources_ros_before_enabling_nounset(self) -> None:
        script = (ROOT / "scripts/verify-tf-smoke.sh").read_text(encoding="utf-8")
        self.assertIn(
            "set -eo pipefail\nsource /opt/ros/humble/setup.bash\nset -u",
            script,
        )

    def test_tf_smoke_launches_robot_state_publisher_through_ros2(self) -> None:
        script = (ROOT / "scripts/verify-tf-smoke.sh").read_text(encoding="utf-8")
        self.assertIn(
            "ros2 run robot_state_publisher robot_state_publisher ",
            script,
        )

    def test_tf_smoke_default_domain_is_valid_for_fast_dds(self) -> None:
        script = (ROOT / "scripts/verify-tf-smoke.sh").read_text(encoding="utf-8")
        match = re.search(r'ROS_DOMAIN_ID="(\d+)"', script)
        self.assertIsNotNone(match)
        self.assertLessEqual(int(match.group(1)), 232)

    def test_tf_smoke_uses_current_clock_joint_state_publisher(self) -> None:
        script = (ROOT / "scripts/verify-tf-smoke.sh").read_text(encoding="utf-8")
        self.assertIn("python3 /deploy/tests/publish_joint_state.py", script)
        self.assertNotIn("stamp: {sec: 1", script)


if __name__ == "__main__":
    unittest.main()
