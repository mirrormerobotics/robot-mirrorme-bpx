#!/usr/bin/env python3
"""Call one shared Robonix Driver command through Atlas.

This is an offline acceptance helper, not part of the BPX runtime. The caller
must provide the fixed Robonix Python API and generated stubs on PYTHONPATH.
"""

from __future__ import annotations

import argparse
import json

import grpc

from robonix_api import ATLAS
from robonix_api.atlas_types import Transport
import lifecycle_pb2
import robonix_contracts_pb2_grpc


COMMANDS = {"init": 0, "activate": 1, "deactivate": 2, "shutdown": 3}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("provider_id")
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("--config-json", default="{}")
    parser.add_argument("--timeout-s", type=float, default=10.0)
    args = parser.parse_args()

    # Fail before opening a channel if a caller supplied malformed config.
    config = json.loads(args.config_json)
    if not isinstance(config, dict):
        raise SystemExit("--config-json must decode to an object")

    binding = ATLAS.connect_capability(
        consumer_id="rbnx-cli/deploy",
        provider_id=args.provider_id,
        contract_id="robonix/lifecycle/driver",
        transport=Transport.GRPC,
    )
    try:
        channel = grpc.insecure_channel(
            binding.endpoint, options=[("grpc.enable_http_proxy", 0)]
        )
        try:
            stub = robonix_contracts_pb2_grpc.RobonixLifecycleDriverStub(channel)
            response = stub.Driver(
                lifecycle_pb2.Driver_Request(
                    command=COMMANDS[args.command],
                    config_json=json.dumps(config, separators=(",", ":")),
                ),
                timeout=args.timeout_s,
            )
        finally:
            channel.close()
    finally:
        binding.close()

    print(
        json.dumps(
            {"ok": response.ok, "state": response.state, "error": response.error},
            sort_keys=True,
        )
    )
    if not response.ok:
        return 1
    expected = {"activate": "active", "deactivate": "inactive"}.get(args.command)
    if expected is not None and response.state.lower() != expected:
        print("unexpected Driver state: expected {}".format(expected))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
