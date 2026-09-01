from __future__ import annotations

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


if __name__ == "__main__":
    unittest.main()
