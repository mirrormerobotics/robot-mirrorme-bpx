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

    def test_default_manifest_pins_the_unified_public_primitive(self) -> None:
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
        self.assertEqual("v0.1.0-dev.3", primitive["branch"])
        self.assertEqual("package_manifest.x86-docker.yaml", primitive["manifest"])
        self.assertEqual("sdk", primitive["config"]["backend"])
        self.assertIs(True, primitive["config"]["allow_motion"])
        self.assertIs(True, primitive["config"]["enable_posture_service"])
        self.assertIs(True, primitive["config"]["enable_motion_service"])
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
        self.assertEqual("0.1.0-dev.3", catalog["version"])
        self.assertEqual("BSD-3-Clause", catalog["license"])
        self.assertIn("posture", catalog["tags"])
        self.assertEqual(["M1chael0919 <2956011381@qq.com>"], catalog["maintainers"])
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

    def test_hardware_guide_covers_manual_read_only_acceptance(self) -> None:
        guide = (ROBOT_ROOT / "HARDWARE_TEST_GUIDE.md").read_text(
            encoding="utf-8"
        )

        self.assertIn("start-sdk-read-only-docker.sh", guide)
        self.assertIn("rbnx caps -v", guide)
        self.assertIn("ros2 topic echo /odom", guide)
        self.assertIn("ros2 topic hz /odom", guide)
        self.assertIn("ros2 topic echo /joint_states", guide)
        self.assertIn("bpx_driver deactivate", guide)
        self.assertIn("bpx_driver activate", guide)
        self.assertIn("docker ps -a --filter name=rbnx_mirrorme_bpx", guide)
        self.assertIn("allow_motion: false", guide)

    def test_posture_probe_is_documented_but_not_in_a_deployment(self) -> None:
        guide = (ROBOT_ROOT / "POSTURE_TEST_GUIDE.md").read_text(encoding="utf-8")
        self.assertIn("run-posture-cycle-probe.sh", guide)
        self.assertIn("--confirm-physical-motion", guide)
        self.assertIn("setStandUp()", guide)
        self.assertIn("setSitDown()", guide)
        self.assertIn("不创建 `JointLevelControl`", guide)
        self.assertIn("不调用 `setVelocity()`", guide)

        for filename in (
            "robonix_manifest.no-motion.yaml",
            "robonix_manifest.fake-state.yaml",
            "robonix_manifest.replay-state.yaml",
            "robonix_manifest.sdk-read-only.yaml",
        ):
            manifest_path = ROBOT_ROOT / filename
            manifest = manifest_path.read_text(encoding="utf-8")
            self.assertNotIn("run-posture-cycle-probe.sh", manifest)
            self.assertNotIn("quadruped/posture", manifest)

        release = yaml.safe_load(
            (ROBOT_ROOT / "robonix_manifest.yaml").read_text(encoding="utf-8")
        )
        self.assertTrue(
            release["primitive"][0]["config"]["enable_posture_service"]
        )

    def test_yaw_circle_probe_is_manual_and_not_in_a_deployment(self) -> None:
        guide = (ROBOT_ROOT / "YAW_CIRCLE_TEST_GUIDE.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("run-yaw-circle-probe.sh", guide)
        self.assertIn("--confirm-physical-yaw-circle", guide)
        self.assertIn("setVelocity(0, 0, yaw)", guide)
        self.assertIn("LegOdom", guide)
        self.assertIn("--opposite-direction-tolerance-rad", guide)
        self.assertIn("反方向", guide)
        self.assertIn("不创建 `JointLevelControl`", guide)

        for manifest_path in ROBOT_ROOT.glob("robonix_manifest*.yaml"):
            manifest = manifest_path.read_text(encoding="utf-8")
            self.assertNotIn("run-yaw-circle-probe.sh", manifest)

    def test_posture_service_guide_distinguishes_test_and_release_profiles(self) -> None:
        guide = (ROBOT_ROOT / "POSTURE_SERVICE_TEST_GUIDE.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("--posture-test", guide)
        self.assertIn("--confirm-physical-posture-service", guide)
        self.assertIn("call-posture-test.sh stand", guide)
        self.assertIn("call-posture-test.sh sit", guide)
        self.assertIn("--release-posture", guide)
        self.assertIn("测试身份不得提交 Catalog", guide)
        self.assertIn("不创建 `JointLevelControl`", guide)

    def test_posture_service_hardware_result_records_both_state_closures(self) -> None:
        result = (ROBOT_ROOT / "POSTURE_SERVICE_VALIDATION.md").read_text(
            encoding="utf-8"
        )
        self.assertIn('"standing confirmed: Motion(6)"', result)
        self.assertIn('"sitting confirmed: LyingDown(0)"', result)
        self.assertIn('"provider_id": "mirrorme_bpx_posture"', result)
        self.assertIn("dev.2 正式发布身份", result)
        self.assertIn("并发 RPC 拒绝", result)


if __name__ == "__main__":
    unittest.main()
