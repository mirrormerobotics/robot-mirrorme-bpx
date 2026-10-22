from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_offline", ROOT / "scripts/verify_offline.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class OfflineVerificationTest(unittest.TestCase):
    def test_full_plan_can_only_start_fake_and_replay(self):
        args = SimpleNamespace(mode="full", primitive_root=ROOT.parent / "primitive",
                               cache_root=Path("/tmp/cache with spaces"), robonix_source=Path("/tmp/robonix"))
        plan = dict(verify.phases(args))
        self.assertEqual(plan["replay"][3], "replay")
        self.assertEqual(plan["fake"][3], "fake")
        self.assertEqual(plan["motion"][3], "motion")
        for command in plan.values():
            self.assertNotIn("--sdk-wheel", command)
            self.assertNotIn("--release-posture", command)
            self.assertNotIn("start-sdk-read-only-docker.sh", " ".join(command))
        self.assertIn("/tmp/cache with spaces/target", plan["replay"])

    def test_failed_phase_stops_suite_and_preserves_report(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "evidence"
            with patch.object(verify, "source_record", return_value={}), \
                    patch.object(verify, "phases", return_value=[("first", []), ("never", [])]), \
                    patch.object(verify, "run_phase", return_value={"status": "failed"}) as run:
                self.assertEqual(verify.main(["--output-dir", str(output)]), 1)
                run.assert_called_once()
            report = json.loads((output / "report.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertFalse(report["hardware_tested"])
            original = (output / "report.json").read_bytes()
            self.assertEqual(verify.main(["--output-dir", str(output)]), 2)
            self.assertEqual((output / "report.json").read_bytes(), original)

    def test_subprocess_failure_and_timeout_are_not_success(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            failed = verify.run_phase("failure", [sys.executable, "-c", "raise SystemExit(7)"], output, 10)
            self.assertEqual(failed["returncode"], 7)
            self.assertEqual(failed["status"], "failed")
            timed_out = verify.run_phase("timeout", [sys.executable, "-c", "import time; time.sleep(30)"], output, 0.1)
            self.assertEqual(timed_out["status"], "timeout")
            self.assertEqual(len(timed_out["log_sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
