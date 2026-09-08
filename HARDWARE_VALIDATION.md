# BPX read-only hardware validation

Validation date: 2026-09-02

Result: **PASS for the bounded, state-only release profile.** This is not a
motion acceptance result. No `MotionLevelControl`, `JointLevelControl`, arm,
posture, move, or velocity command path was created or invoked.

## Fixed inputs

- Robot test address: `192.168.1.237` (temporary WLAN address)
- BPX SDK: `1.0.8`, source commit
  `19cb373a8d2f8e19eaab6a1441167f3287cc95dd`
- SDK wheel SHA-256:
  `6a0bcb708c55605dfbfeead6c84141f474505f1c01efbdb564e3dfa4549889c7`
- Robonix: `f6cacfc4b402eb57c75b553d375c6cfaba11dce7`
- Final rebuilt Primitive runtime image:
  `sha256:63f528776b1af6e50ae334367102a9ff73968502a39228cf616a5176b9b102a6`
- ROS domain used by the integrated test: `223`

The SDK reported robot software version `1.0.15`, commit `90561076`, built on
2026-08-28 at 15:23:13. This value is recorded as an SDK-reported software
build, not as a substitute for the product's formal model, serial number, or
motion-controller firmware record.

## Observed platform and network

The robot computer reported Ubuntu 20.04.6 LTS, Linux 5.15.147, AArch64, eight
Cortex-A55 CPUs, 1.9 GiB RAM, and no swap. Its relevant interfaces were:

- `wlan0`: `192.168.1.237/24`, MAC `04:fa:49:92:02:0d`
- `enp1s0`: `10.21.20.1/24`, link down
- `wlan1`: `10.21.40.1/24`
- `eth0`: `10.21.32.120/24`
- default route: `192.168.1.1` through `wlan0`

The test host reached `192.168.1.237` directly through local address
`192.168.1.63` on `eth4`; the route did not use a gateway. The development
host was Ubuntu 20.04.6 under WSL2, x86_64, Intel Core i5-14600K, 20 logical
CPUs and 15 GiB RAM. Docker Desktop Engine/CLI was `29.7.2`, Linux/amd64.

This is a Docker Desktop development-host result. It is not the separate
native Ubuntu 22.04 production-host acceptance required before final release.

## Standalone SDK telemetry

The bounded probe constructed only `bpx_sdk.RequestRobotState`. It reached a
TCP connection and received the first odometry frame in approximately
0.064--0.120 seconds. Leg odometry, IMU, all 12 joints, motor/driver
temperatures, motion state/gait, battery, and all available vendor timestamps
were present. The robot remained in motion state `0`, gait `0` during the
stationary capture.

Two local recordings were audited. Raw recordings stay under the ignored
Primitive `.artifacts/hardware/2026-09-02-192.168.1.237/` directory and are
not release artifacts.

| Requested upload rate | Host duration | Frames | Maximum host event gap | Disconnects | Timestamp regressions |
| --- | ---: | ---: | ---: | ---: | ---: |
| 50 Hz | 29.999 s | 1676 | 0.0621 s | 0 | 0 |
| 10 Hz | 9.984 s | 127 | 0.1029 s | 0 | 0 |

At a requested 50 Hz, observed field-change rates were approximately:

- joint state: 54.87 Hz;
- IMU: 52.17 Hz;
- leg odometry: 11.10 Hz;
- motion state: 5.53 Hz;
- battery/temperature: 1.10 Hz.

At a requested 10 Hz, joint, IMU, and odometry each changed at approximately
10.92 Hz, motion state at 5.41 Hz, and battery/temperature at 1.00 Hz. The
auditor estimated no missing odometry updates in either run. The 50 Hz run
estimated 21 skipped joint and 102 skipped IMU native updates; the 10 Hz run
estimated none.

The normalized odometry quaternion norm remained `1.0`. Stationary IMU
acceleration magnitude had a median of about `9.73 m/s^2`. These observations
show internally plausible data, but do not prove the physical axis convention,
IMU extrinsic, joint sign/zero, or URDF-to-hardware match.

All vendor counters were monotonic, but they advanced about 1.09--1.11
reported units per host millisecond. Their names and nominal deltas resemble
milliseconds, but the measured scale does not support treating them as an
accurate ROS wall clock. Unit, epoch, wrap/reset behavior, and the discrepancy
with the native-rate documentation still require vendor clarification.

`RequestRobotState.connect()` also reported the SDK's automatic robot-time-sync
handling. This is part of the vendor read-only state session even though no
actuator command is available; its exact action-code semantics should be
confirmed with the SDK/firmware owner.

## Integrated Robonix deployment

The local `robonix_manifest.sdk-read-only.yaml` configuration was copied to a
temporary test manifest with robot IP `192.168.1.237`. The integrated boot
reached:

```text
atlas: ACTIVE
soma: ACTIVE
mirrorme_bpx_state: ACTIVE
```

`rbnx caps -v` exposed only the shared lifecycle Driver and
`robonix/primitive/quadruped/odom` for `mirrorme_bpx_state`. It did not expose
`twist_in`, posture, move, joint control, navigation, or mapping capabilities.

A live `nav_msgs/Odometry` message was received on `/odom` with `frame_id=odom`
and `child_frame_id=base_link`. A live `sensor_msgs/JointState` message was
received on `/joint_states` with all 12 official joint names, 12 positions, 12
velocities, and an intentionally empty effort array.

The shared Driver completed this sequence:

```text
ACTIVE -> INACTIVE -> ACTIVE -> TERMINATED
```

After reactivation, a new `/odom` sample was received. `rbnx shutdown` exited
the outer boot container with status 0, invoked `Driver(CMD_SHUTDOWN)`, and left
no BPX Primitive child container behind.

The parameterized `scripts/start-sdk-read-only-docker.sh` launcher was then
validated against the same robot. With only the pinned wheel and robot IP
provided, it detected Docker Desktop, selected bridge mode, resolved gateway
`172.17.0.1`, generated the motion-disabled manifest, and brought Atlas, Soma
and `mirrorme_bpx_state` to `ACTIVE` in about five seconds. `rbnx caps -v`
contained `quadruped/odom` and no `twist_in`; an independent consumer received
a live `odom` to `base_link` message. Ctrl-C performed Driver shutdown, removed
both containers, and deleted the temporary manifest directory.

An initial shutdown run exposed an exit-time native-thread race after the
provider had already reached `TERMINATED`. The provider now explicitly stops
the Robonix ROS executor after disconnecting the SDK. The same hardware
`CMD_SHUTDOWN` was repeated: the package reported a successful process exit,
with no native termination message or child container left behind.

## Docker Desktop finding

Docker Desktop did not deliver the robot's UDP state upload to a
`--network host` Primitive container. A bridge container with an explicit
`9873:9873/udp` mapping worked. The integrated topology additionally required
Atlas to listen on a bridge-reachable address and the Primitive to advertise
its bridge-container IPv4 address. The start wrapper now supports:

- `BPX_DOCKER_NETWORK_MODE=bridge`;
- `BPX_DOCKER_STATE_UDP_PORT=9873`;
- `BPX_DOCKER_HOST_ADDRESS=<Docker bridge gateway>`.

Native Linux Docker should continue to use the default host-network path. The
Docker Desktop overrides are development-host settings, not portable values to
copy into the Catalog manifest.

## Operator-confirmed odometry directions — 2026-09-08

The onsite operator confirmed the following by comparing physical robot motion
with actual odometry output: positive x is forward, positive y is left, and
positive yaw is a left turn. The operator explicitly clarified that this was
observed output, not just the joystick or velocity-command convention.

This is operator-reported acceptance evidence. No raw capture, video, exact
field names, or artifact hash was supplied for this follow-up, so it is not
attributed to a new wheel or firmware baseline. It closes the direction check
used as the Catalog Draft gate. World-frame origin, initial heading, and
reconnect/reboot reset behavior remain unverified; world position x must not
be interpreted as robot-forward displacement at every heading.

## Still open

- formal BPX model, serial number, and motion-controller firmware record;
- physical operator, emergency-stop, controller-priority, and site-safety
  verification;
- odometry world-frame origin/reset behavior, joint sign/zero, IMU frame/extrinsic,
  temperature/current units, and covariance sources;
- vendor timestamp semantics and observed upload-rate differences;
- unplug/replug, robot reboot, firewall, long-duration soak, and native Ubuntu
  22.04 host tests;
- visual/mechanical confirmation that the pinned URDF matches this unit;
- every motion-related item in `ACCEPTANCE.md`.
