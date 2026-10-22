#!/usr/bin/env python3
"""Run BPX offline checks and save an auditable report; never load the SDK."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
BASELINE = "f6cacfc4b402eb57c75b553d375c6cfaba11dce7"


def command_output(command, cwd):
    return subprocess.check_output(command, cwd=str(cwd), text=True).strip()


def interrupted(_signum, _frame):
    raise KeyboardInterrupt()


def source_record(path):
    """Record HEAD and hashes of tracked/non-ignored files, including local edits."""
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=str(path),
    ).decode().split("\0")
    hashes = {}
    for name in sorted(set(filter(None, names))):
        file = path / name
        if file.is_file():
            hashes[name] = hashlib.sha256(file.read_bytes()).hexdigest()
        elif not file.exists():
            hashes[name] = None
    return {
        "path": str(path), "commit": command_output(["git", "rev-parse", "HEAD"], path),
        "status": command_output(["git", "status", "--short"], path),
        "files_sha256": hashes,
    }


def phases(args):
    """Only replay and fake-backed profiles are reachable through this entry point."""
    primitive = args.primitive_root
    commands = [
        ("primitive-unit", ["bash", str(primitive / "scripts/test.sh")]),
        ("robot-unit", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"]),
        ("model-generation", [sys.executable, "scripts/generate_deployment_urdf.py", "--check"]),
    ]
    if args.mode == "unit":
        return commands
    cache = args.cache_root
    cache_args = ["--target-cache", str(cache / "target"), "--cargo-cache", str(cache / "cargo"),
                  "--config-cache", str(cache / "config")]
    commands += [
        ("docker-ready", ["docker", "version"]),
        ("runtime-build", ["bash", str(primitive / "scripts/build-container.sh")]),
        ("model", ["bash", "scripts/verify-model.sh"]),
        ("tf", ["bash", "scripts/verify-tf-smoke.sh"]),
        ("robonix-toolchain", ["bash", str(primitive / "scripts/verify-rbnx.sh"),
                               str(args.robonix_source)] + cache_args),
    ]
    for profile in ("replay", "fake", "motion"):
        commands.append((profile, ["bash", "scripts/test-offline-integration.sh",
                                  str(args.robonix_source), profile] + cache_args))
    commands.append(("image-versions", ["docker", "image", "inspect",
                                         "primitive-mirrorme-bpx-quadruped-rbnx:dev",
                                         "mirrorme-bpx-rbnx-codegen:dev",
                                         "--format", "{{.Id}} {{json .RepoDigests}}"] ))
    return commands


def run_phase(name, command, output, timeout):
    """Bound a process group; allow shell cleanup traps to run on interruption."""
    log = output / (name + ".log")
    result = {"name": name, "command": command, "log": log.name, "status": "failed"}
    started = time.monotonic()
    print("Running {} (log: {})".format(name, log), flush=True)
    with log.open("x", encoding="utf-8") as stream:
        process = subprocess.Popen(command, cwd=str(ROOT), stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result["returncode"] = process.wait(timeout=timeout)
            result["status"] = "passed" if result["returncode"] == 0 else "failed"
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
            result["status"] = "timeout" if isinstance(exc, subprocess.TimeoutExpired) else "interrupted"
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=45)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    result["duration_s"] = round(time.monotonic() - started, 3)
    result["log_sha256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    print("{}: {}".format(name, result["status"]), flush=True)
    return result


def parser():
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--mode", choices=("unit", "full"), default="unit")
    value.add_argument("--robonix-source", type=Path, default=ROOT.parent / ".deps/robonix")
    value.add_argument("--cache-root", type=Path, default=Path.home() / ".cache/robonix-bpx")
    value.add_argument("--output-dir", type=Path,
                       help="New evidence directory; refuses to reuse an existing directory")
    value.add_argument("--timeout-s", type=int, default=3600, help="Maximum seconds per phase")
    return value


def main(argv=None):
    args = parser().parse_args(argv)
    args.primitive_root = ROOT.parent / "primitive-mirrorme-bpx-quadruped-rbnx"
    if os.name != "posix":
        parser().error("run this command inside Linux/WSL (see OFFLINE_DEVELOPMENT.md)")
    if args.timeout_s <= 0:
        parser().error("--timeout-s must be positive")
    for key in ("primitive_root", "robonix_source", "cache_root"):
        setattr(args, key, getattr(args, key).resolve())
    now = datetime.now(timezone.utc)
    output = (args.output_dir or ROOT / ".artifacts/offline" / now.strftime("%Y%m%dT%H%M%S%fZ")).resolve()
    report = {"schema": "mirrorme-bpx-offline-v1", "started_at": now.isoformat(),
              "mode": args.mode, "host": platform.platform(), "python": sys.version,
              "status": "failed", "hardware_tested": False, "phases": []}
    try:
        # A report must never overwrite earlier evidence, even on failure.
        output.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        report["sources"] = {"robot": source_record(ROOT), "primitive": source_record(args.primitive_root)}
        if args.mode == "full":
            actual = command_output(["git", "rev-parse", "HEAD"], args.robonix_source)
            if actual != BASELINE:
                raise ValueError("unexpected Robonix commit: " + actual)
            report["robonix_commit"] = actual
        for name, command in phases(args):
            result = run_phase(name, command, output, args.timeout_s)
            report["phases"].append(result)
            if result["status"] != "passed":
                break
        else:
            report["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError, KeyboardInterrupt) as exc:
        report["error"] = str(exc) or "interrupted"
    finally:
        signal.signal(signal.SIGTERM, previous)
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("Report: {}".format(output / "report.json"), flush=True)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
