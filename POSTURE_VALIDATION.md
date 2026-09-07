# BPX stand/hold/sit hardware validation

This record covers the first bounded `MotionLevelControl` posture cycle. It is
separate from the read-only validation in `HARDWARE_VALIDATION.md` and is not a
Robonix `posture` capability acceptance result.

## Test baseline

- Time: `2026-09-03T14:20:20+08:00`
- Robot: BPX at temporary WLAN address `192.168.1.237`
- Host route: `192.168.1.237 dev eth4 src 192.168.1.63`
- Container network: Docker bridge with explicit `9873:9873/udp`
- SDK: `bpx_sdk_open` v1.0.8 wheel
- Wheel SHA-256: `6a0bcb708c55605dfbfeead6c84141f474505f1c01efbdb564e3dfa4549889c7`
- Primitive image: `primitive-mirrorme-bpx-quadruped-rbnx:dev`

Before motion, two ICMP probes succeeded with zero loss, no Docker container
was running, and host UDP 9873 had no listener. The narrow wheel check passed:
`MotionLevelControl` exposed all 15 inherited state methods and the four used
setup/posture methods; `MotionState.LyingDown` was 0 and `MotionState.Motion`
was 6.

## Command boundary

The probe created one `MotionLevelControl` owner. It enabled no velocity mode
and called only `setStandUp()` and `setSitDown()` as motion requests. It did
not construct `JointLevelControl` and did not call `setVelocity()`,
`setZeroPositionsFlag()`, gait, damping, flip, jump, or joint command APIs.

The executed command was:

```bash
BPX_DOCKER_NETWORK_MODE=bridge \
  bash scripts/run-posture-cycle-probe.sh \
    /root/workspace/c2/bpx_sdk_open/main/wheelhouse/bpx_sdk_open-1.0.8-cp310-cp310-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl \
    --robot-ip 192.168.1.237 \
    --robot-state-port 9873 \
    --state-rate-hz 50 \
    --motion-command-rate-hz 50 \
    --hold-duration-s 3 \
    --confirm-physical-motion
```

## Observed software trace

```text
robot state udp receiver listening on port 9873
automatic robot time sync handled action=3 offset_ms=-2504
initial state confirmed: LyingDown(0)
setStandUp accepted; waiting for Motion(6)
state confirmed: Motion(6)
standing confirmed; holding for 3.000s
setSitDown accepted; waiting for LyingDown(0)
state confirmed: LyingDown(0)
posture cycle complete: LyingDown(0)
server closed connection
```

The command exited with status 0. Afterward, the named probe container was
absent, UDP 9873 was free, and the robot still answered ICMP with a 6.66 ms
round trip.

## Result and remaining evidence

The SDK/state-machine acceptance passed for one complete
`LyingDown(0) -> Motion(6) -> three-second hold -> LyingDown(0)` cycle. This
proves the tested command and state-feedback path on this robot/software
baseline.

Remote logs alone cannot prove physical smoothness, absence of translation,
ground contact, or safe clearance. The onsite operator subsequently confirmed
that the robot stood and lay down normally, without observed unexpected
translation, instability, noise, or another anomaly. No video evidence was
captured by this test runner, so this remains an operator observation rather
than independently reviewable visual evidence.

The same bounded posture runtime is included in the `v0.1.0-dev.2` release
identity alongside odom. A subsequent sequential Robonix `posture` stand/sit
RPC hardware check passed and is recorded separately in
[POSTURE_SERVICE_VALIDATION.md](POSTURE_SERVICE_VALIDATION.md). The release
still exposes no `twist_in`, `move`, or joint-level command. Live fault
injection remains future hardening work.
A separate manual yaw-only test now exercises `setVelocity(0,0,yaw)`, but the
general Robonix `twist_in` mapping remains deferred and `JointLevelControl`
stays out of scope.
