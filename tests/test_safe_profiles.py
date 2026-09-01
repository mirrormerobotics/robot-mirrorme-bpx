from __future__ import annotations

from pathlib import Path
import unittest

import yaml


ROBOT_ROOT = Path(__file__).resolve().parents[1]


class SafeProfilesTest(unittest.TestCase):
    def test_repository_uses_bsd_3_clause(self) -> None:
        license_text = (ROBOT_ROOT / "LICENSE").read_text(encoding="utf-8")
        readme = (ROBOT_ROOT / "README.md").read_text(encoding="utf-8")

        self.assertIn("BSD 3-Clause License", license_text)
        self.assertIn("Hangzhou MirrorMe Technology Co., Ltd.", license_text)
        self.assertIn("License: BSD-3-Clause", readme)

    def test_default_manifest_pins_the_read_only_public_primitive(self) -> None:
        manifest = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual("robonix.robot.mirrorme.bpx", manifest["name"])
        self.assertEqual("${BPX_SDK_WHEEL}", manifest["env"]["BPX_SDK_WHEEL"])
        self.assertEqual(1, len(manifest["primitive"]))
        primitive = manifest["primitive"][0]
        self.assertEqual(
            "https://github.com/mirrormerobotics/primitive-mirrorme-bpx-quadruped-rbnx",
            primitive["url"],
        )
        self.assertEqual("v0.1.0-dev.1", primitive["branch"])
        self.assertEqual("package_manifest.x86-docker.yaml", primitive["manifest"])
        self.assertEqual("sdk", primitive["config"]["backend"])
        self.assertIs(False, primitive["config"]["allow_motion"])
        self.assertIs(False, primitive["config"]["publish_odom_tf"])
        self.assertEqual([], manifest["service"])
        self.assertEqual([], manifest["skill"])
        self.assertIn("atlas", manifest["system"])
        self.assertIn("soma", manifest["system"])

    def test_default_manifest_has_complete_catalog_metadata(self) -> None:
        manifest = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.yaml").read_text(encoding="utf-8")
        )
        catalog = manifest["catalog"]

        self.assertEqual(manifest["name"], catalog["name"])
        self.assertEqual("0.1.0-dev.1", catalog["version"])
        self.assertEqual("BSD-3-Clause", catalog["license"])
        self.assertIn("read-only", catalog["tags"])
        self.assertEqual(["nonkr <nonkr@hotmail.com>"], catalog["maintainers"])
        self.assertTrue(catalog["description"])

    def test_fake_profile_selects_distinct_motion_development_package(self) -> None:
        manifest = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.fake-state.yaml").read_text(
                encoding="utf-8"
            )
        )
        primitive = manifest["primitive"][0]
        self.assertEqual("package_manifest.motion-dev.yaml", primitive["manifest"])
        self.assertEqual("fake", primitive["config"]["backend"])
        self.assertIs(False, primitive["config"]["allow_motion"])

    def test_replay_profile_is_read_only_and_uses_packaged_fixture(self) -> None:
        manifest = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.replay-state.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(1, len(manifest["primitive"]))
        primitive = manifest["primitive"][0]
        self.assertEqual("package_manifest.state-replay.yaml", primitive["manifest"])
        self.assertEqual("replay", primitive["config"]["backend"])
        self.assertIs(False, primitive["config"]["allow_motion"])
        self.assertIs(True, primitive["config"]["publish_odom_tf"])
        self.assertTrue(
            primitive["config"]["replay_path"].endswith("replay_nominal.jsonl")
        )

    def test_offline_harness_covers_driver_cycle_and_both_state_topics(self) -> None:
        harness = (ROBOT_ROOT / "scripts" / "test-offline-integration.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('"${DRIVER_DOCKER_ARGS[@]}" deactivate', harness)
        self.assertIn('"${DRIVER_DOCKER_ARGS[@]}" activate', harness)
        self.assertIn("ros2 topic echo /odom", harness)
        self.assertIn("ros2 topic echo /joint_states", harness)
        self.assertIn("ros2 topic echo /tf", harness)
        self.assertIn("quadruped/twist_in", harness)


if __name__ == "__main__":
    unittest.main()
