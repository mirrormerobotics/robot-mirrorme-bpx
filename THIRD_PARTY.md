# Third-party provenance and notices

## Robonix

- Source baseline: `syswonder/Robonix@f6cacfc4b402eb57c75b553d375c6cfaba11dce7`
- Used as an external fixed build/runtime input; its source is not copied into
  this deployment directory.
- Redistribution, catalog submission, and binary release must retain the
  notices required by the selected upstream components.

## MirrorMe BPX model

- Source: `mirrormerobotics/BPX@ea4f0013518dc7fe488a32706652a1d66a4d8bdd`
- License: BSD-3-Clause
- Imported URDF/mesh files, upstream license, provenance, and per-file hashes
  are under `description/bpx/`.

## BPX SDK

- Contract baseline: `mirrormerobotics/bpx_sdk_open@19cb373a8d2f8e19eaab6a1441167f3287cc95dd`
- License: Apache-2.0
- The x86_64 wheel is not stored in this workspace or runtime image. It is
  supplied externally, checksum-verified, and mounted read-only.
- The SDK repository license covers its headers, shared libraries, examples,
  Python bindings, and wheels. Its Apache NOTICE and applicable third-party
  notices must accompany any redistributed SDK artifact.
- A release SBOM and the SDK's internal native-library dependency audit remain
  required before publishing a Docker image that embeds the SDK wheel.

## Container base

- Runtime base: `ros:humble-ros-base` pinned by digest in the Primitive
  Dockerfile.
- The image contains ROS 2 and Python dependencies under their respective
  upstream licenses. Produce a release SBOM and approved notice bundle before
  distributing an immutable release image.
