from __future__ import annotations

import os
from pathlib import Path
import unittest

import yaml


ROBOT_ROOT = Path(__file__).resolve().parents[1]


class SdkReadOnlyManifestTest(unittest.TestCase):
    def test_profile_selects_the_read_only_package_and_disables_motion(self) -> None:
        profile = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.sdk-read-only.yaml").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual("${BPX_SDK_WHEEL}", profile["env"]["BPX_SDK_WHEEL"])
        self.assertEqual(1, len(profile["primitive"]))
        primitive = profile["primitive"][0]
        self.assertEqual(
            "package_manifest.sdk-read-only.yaml", primitive["manifest"]
        )
        self.assertEqual("sdk", primitive["config"]["backend"])
        self.assertIs(False, primitive["config"]["allow_motion"])
        self.assertIs(False, primitive["config"]["auto_arm_fake"])
        self.assertIs(False, primitive["config"]["publish_odom_tf"])

    def test_docker_launcher_defaults_to_a_motion_disabled_full_deployment(self) -> None:
        launcher = (
            ROBOT_ROOT / "scripts" / "start-sdk-read-only-docker.sh"
        )
        launcher_text = launcher.read_text(encoding="utf-8")

        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertIn("--sdk-wheel", launcher_text)
        self.assertIn("--robot-ip", launcher_text)
        self.assertIn("--network-mode", launcher_text)
        self.assertIn("backend: sdk", launcher_text)
        self.assertIn('ALLOW_MOTION="false"', launcher_text)
        self.assertIn('ENABLE_POSTURE_SERVICE="false"', launcher_text)
        self.assertIn("package_manifest.sdk-read-only.yaml", launcher_text)
        self.assertIn("atlas:", launcher_text)
        self.assertIn("soma:", launcher_text)
        self.assertIn("BPX_DOCKER_STATE_UDP_PORT", launcher_text)
        self.assertIn("/target/release/rbnx boot", launcher_text)
        self.assertNotIn("package_manifest.motion-dev.yaml", launcher_text)

    def test_docker_launcher_requires_two_explicit_posture_test_gates(self) -> None:
        launcher_text = (
            ROBOT_ROOT / "scripts" / "start-sdk-read-only-docker.sh"
        ).read_text(encoding="utf-8")
        client = ROBOT_ROOT / "scripts" / "call-posture-test.sh"
        client_text = client.read_text(encoding="utf-8")

        self.assertIn("--posture-test", launcher_text)
        self.assertIn("--release-posture", launcher_text)
        self.assertIn("--confirm-physical-posture-service", launcher_text)
        self.assertIn("package_manifest.posture-test.yaml", launcher_text)
        self.assertIn('ALLOW_MOTION="true"', launcher_text)
        self.assertIn('ENABLE_POSTURE_SERVICE="true"', launcher_text)
        self.assertIn("I_UNDERSTAND_POSTURE_RPC_CAN_MOVE_BPX", launcher_text)
        self.assertIn("package_manifest.x86-docker.yaml", launcher_text)
        self.assertTrue(os.access(client, os.X_OK))
        self.assertIn("bpx_quadruped.posture_client", client_text)
        self.assertIn("stand|sit", client_text)


if __name__ == "__main__":
    unittest.main()
