from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CommandLineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bpx cli test ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.log = self.work / "commands.jsonl"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        # Only these fake executables are reachable as Docker/rbnx in tests.
        docker = self.bin / "docker"
        docker.write_text("""#!/usr/bin/env python3
import json, os, re, sys
with open(os.environ["CLI_TEST_LOG"], "a") as stream:
    stream.write(json.dumps({"argv": sys.argv[1:], "env": {
        key: os.environ.get(key) for key in ("BPX_REQUIRED_BACKEND", "BPX_POSTURE_CAPABILITY")
    }}) + "\\n")
if "--name" in sys.argv:
    name = sys.argv[sys.argv.index("--name") + 1]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
        print("invalid Docker container name: " + name, file=sys.stderr)
        sys.exit(125)
if os.environ.get("CLI_TEST_OFFLINE") == "1":
    if sys.argv[1] == "inspect":
        if "--format" in sys.argv:
            print("true" if any(".State.Running" in arg for arg in sys.argv) else
                  "robonix.primitive.mirrorme.bpx.quadruped")
            sys.exit(0)
        sys.exit(1)
    if sys.argv[1] == "exec":
        print("mirrorme_bpx_replay quadruped/odom")
    if sys.argv[1] == "run" and "info" in sys.argv and "/odom" in sys.argv:
        print("Publisher count: 1")
    sys.exit(0)
if len(sys.argv) > 1 and sys.argv[1] == "inspect":
    if os.environ.get("CLI_TEST_EXISTING") == "1":
        if "--format" in sys.argv:
            print(os.environ.get("CLI_TEST_LABEL", "robonix.primitive.mirrorme.bpx.quadruped"))
        sys.exit(0)
    sys.exit(1)
""")
        docker.chmod(0o755)
        rbnx = self.bin / "rbnx"
        rbnx.write_text("#!/bin/bash\nprintf '%s\\n' /tmp/fake-robonix-api\n")
        rbnx.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("BPX_", "RBNX_", "ROBONIX_", "CLI_"))}
        self.env.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        CLI_TEST_LOG=str(self.log))

    def run_script(self, name, *args, env=None):
        return subprocess.run(["bash", str(ROOT / "scripts" / name), *map(str, args)],
                              env={**self.env, **(env or {})}, cwd=self.work,
                              text=True, capture_output=True, timeout=10)

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_every_operator_script_has_side_effect_free_help(self):
        for script in sorted((ROOT / "scripts").glob("*.sh")):
            with self.subTest(script=script.name):
                result = self.run_script(script.name, "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Usage:", result.stdout)
        self.assertEqual(self.calls(), [])

    def test_shell_syntax(self):
        for script in (ROOT / "scripts").rglob("*.sh"):
            result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_values_fail_before_docker(self):
        candidates = [("start-sdk-read-only-docker.sh", "--runtime-image"),
                      ("record-odom-stage.sh", "--image")]
        for script, option in candidates:
            if not (ROOT / "scripts" / script).exists():
                continue
            for suffix in ([], ["--robot-ip", "192.168.1.237"]):
                result = self.run_script(script, option, *suffix)
                self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_unknown_option_fails_before_docker(self):
        script = "start.sh" if (ROOT / "scripts/start.sh").exists() else "verify-tf-smoke.sh"
        result = self.run_script(script, "--does-not-exist")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_tf_arguments_override_environment(self):
        result = self.run_script("verify-tf-smoke.sh", "--image", "custom:tf",
                                 "--ros-domain-id=222", "--container-name", "tf-custom",
                                 env={"BPX_TF_TEST_IMAGE": "ignored:image"})
        self.assertEqual(result.returncode, 0, result.stderr)
        run = self.calls()[0]["argv"]
        self.assertIn("custom:tf", run)
        self.assertIn("ROS_DOMAIN_ID=222", run)
        self.assertIn("tf-custom", run)

    def test_tf_default_container_names_are_valid_and_unique(self):
        for _ in range(2):
            result = self.run_script("verify-tf-smoke.sh")
            self.assertEqual(result.returncode, 0, result.stderr)
        names = [call["argv"][call["argv"].index("--name") + 1]
                 for call in self.calls() if call["argv"][0] == "run"]
        self.assertEqual(len(set(names)), 2)
        for name in names:
            self.assertRegex(name, r"^rbnx_mirrorme_bpx_tf_test_[0-9]+$")

    def test_posture_rpc_uses_selected_container_and_source_paths(self):
        result = self.run_script("call-posture-test.sh", "stand", "provider_1",
                                 "--container-name", "deployment_1",
                                 "--robonix-source", "/source with spaces",
                                 "--primitive-root", "/primitive with spaces",
                                 env={"CLI_TEST_EXISTING": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        execution = next(c["argv"] for c in self.calls() if c["argv"][0] == "exec")
        self.assertIn("deployment_1", execution)
        self.assertIn("BPX_POSTURE_PROVIDER_ID=provider_1", execution)
        self.assertIn("BPX_ROBONIX_SOURCE=/source with spaces", execution)

    def test_deployment_posture_still_needs_explicit_acknowledgement(self):
        result = self.run_script("start-sdk-read-only-docker.sh",
                                 "--sdk-wheel", "/not-used.whl", "--robot-ip", "192.168.1.237",
                                 "--posture-test")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--confirm-physical-posture-service", result.stderr)
        self.assertEqual(self.calls(), [])

    def deployment_fixture(self):
        # Copy the launcher to a disposable workspace; never boot the real project.
        primitive = self.work / "primitive-mirrorme-bpx-quadruped-rbnx"
        primitive.mkdir()
        primitive_source = ROOT.parent / "primitive-mirrorme-bpx-quadruped-rbnx"
        if not primitive_source.is_dir():
            self.skipTest("cross-repository launcher needs the Primitive sibling")
        (primitive / "scripts").symlink_to(primitive_source / "scripts", target_is_directory=True)
        (primitive / "sdk").mkdir()
        wheel = self.work / "sdk.whl"
        wheel.write_bytes(b"fake SDK; all Docker commands are intercepted")
        (primitive / "sdk/SHA256SUMS").write_text(hashlib.sha256(wheel.read_bytes()).hexdigest() + "  sdk.whl\n")
        robot = self.work / "robot-mirrorme-bpx"
        (robot / "scripts").mkdir(parents=True)
        launcher = robot / "scripts/start-sdk-read-only-docker.sh"
        shutil.copy2(ROOT / "scripts/start-sdk-read-only-docker.sh", launcher)
        shutil.copytree(ROOT / "scripts/lib", robot / "scripts/lib")
        source = self.work / "robonix source"
        (source / ".git").mkdir(parents=True)
        git = self.bin / "git"
        git.write_text('#!/bin/bash\nif [[ "$*" == *rev-parse* ]]; then printf "%s\\n" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi\n')
        git.chmod(0o755)
        return robot, launcher, source, wheel

    def test_deployment_passes_custom_tool_settings_to_preparation_and_runtime(self):
        _, launcher, source, wheel = self.deployment_fixture()
        result = subprocess.run([
            "bash", str(launcher), "--sdk-wheel", str(wheel), "--robot-ip", "192.168.1.237",
            "--network-mode", "host", "--robonix-source", str(source),
            "--expected-commit", "a" * 40, "--tool-image", "custom:tool",
            "--runtime-image", "custom:runtime", "--container-name", "outer-test",
            "--primitive-container", "inner-test", "--target-cache", str(self.work / "target"),
            "--cargo-cache", str(self.work / "cargo"), "--config-cache", str(self.work / "config"),
        ], env={**self.env, "TMPDIR": str(self.work)}, cwd=self.work,
            text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [call["argv"] for call in self.calls()]
        build = next(cmd for cmd in commands if cmd[0] == "build")
        self.assertIn("custom:tool", build)
        outer = next(cmd for cmd in commands if "outer-test" in cmd and cmd[0] == "run")
        self.assertIn("custom:tool", outer)
        self.assertIn("BPX_RBNX_IMAGE=custom:runtime", outer)
        self.assertIn("BPX_RBNX_CONTAINER=inner-test", outer)
        for cmd in [cmd for cmd in commands if cmd[0] == "run"]:
            self.assertIn(str(self.work / "target") + ":/target", cmd)
            self.assertIn(str(self.work / "cargo") + ":/cargo", cmd)
            self.assertIn(str(self.work / "config") + ":/root/.robonix", cmd)

    def relative_cache_fixture(self):
        config = self.work / "existing config"
        config.mkdir()
        (self.work / "config-link").symlink_to(config, target_is_directory=True)
        return ("target", "cargo with spaces", "config-link")

    def assert_absolute_cache_mounts(self, caches):
        runs = [call["argv"] for call in self.calls()
                if call["argv"][0] == "run" and
                any(arg.endswith(":/target") for arg in call["argv"])]
        self.assertTrue(runs)
        for run in runs:
            for cache, destination in zip(caches, ("/target", "/cargo", "/root/.robonix")):
                expected = str((self.work / cache).resolve()) + ":" + destination
                self.assertIn(expected, run)

    def test_deployment_resolves_relative_caches_before_preparation_and_runtime(self):
        _, launcher, source, wheel = self.deployment_fixture()
        caches = self.relative_cache_fixture()
        result = subprocess.run([
            "bash", str(launcher), "--sdk-wheel", str(wheel), "--robot-ip", "192.168.1.237",
            "--network-mode", "host", "--robonix-source", str(source),
            "--expected-commit", "a" * 40, "--target-cache", caches[0],
            "--cargo-cache", caches[1], "--config-cache", caches[2],
        ], env={**self.env, "TMPDIR": str(self.work)}, cwd=self.work,
            text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_absolute_cache_mounts(caches)

    def test_offline_integration_resolves_relative_cache_mounts(self):
        robot, _, source, _ = self.deployment_fixture()
        launcher = robot / "scripts/test-offline-integration.sh"
        shutil.copy2(ROOT / "scripts/test-offline-integration.sh", launcher)
        caches = self.relative_cache_fixture()
        target = self.work / caches[0] / "release"
        target.mkdir(parents=True)
        rbnx = target / "rbnx"
        rbnx.write_text("#!/bin/bash\nexit 0\n")
        rbnx.chmod(0o755)
        result = subprocess.run([
            "bash", str(launcher), "--robonix-source", str(source),
            "--expected-commit", "a" * 40, "--target-cache", caches[0],
            "--cargo-cache", caches[1], "--config-cache", caches[2],
        ], env={**self.env, "CLI_TEST_OFFLINE": "1"}, cwd=self.work,
            text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("offline replay integration: PASS", result.stdout)
        self.assert_absolute_cache_mounts(caches)
