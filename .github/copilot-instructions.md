# Copilot instructions for mib-cluster-map

## Project overview

This repository is a firmware customization project for VW/SEAT/Skoda/Audi MIB2 and MIB2.5 head units. The project injects a secondary display into Android Auto's `gal` process, forwards that video stream to a local player, and renders it into the cluster as if it were the car's own map.

The key system flow is described in `docs/Development.md`:

- `src/` contains the preload hook (`libgal_hook.so`) and the firmware-specific profile logic.
- `player/` contains the decoder/rendering side (`stream-player`) that consumes the forwarded H.264 stream and draws it into the cluster window.
- `scripts/`, `greenmenu/`, and `swdl/` implement installation, status checks, green-menu entries, and the software-update flow.
- `config/` and `src/firmware_profiles.h` hold the known firmware profiles and supported-train metadata.
- `tools/` contains host-side helpers for porting and verification.
- `thirdparty/` contains vendored Android Auto and CarPlay support code.

This repo is not a general app ecosystem; most meaningful work is firmware- and profile-specific, and many changes depend on real unit logs or captured `gal` files.

## Build, test, and validation commands

### Production build

```sh
./build_local.sh
```

Builds the hook, player, packaging, and generated SD-card release artifacts. The script runs in Docker and expects the QNX 6.5 ARMv7 toolchain image. The release output lands in `dist/`, and the SD-card layout is assembled under `dist/sdcard/`.

Targeted build variants:

```sh
./build_local.sh hook
./build_local.sh player
```

- `hook`: builds `libgal_hook.so` and `libdmdt_flush.so`.
- `player`: builds the stream player and its FFmpeg dependency if needed.

### Host-side validation that exists in-repo

There is no repo-wide test suite or lint command; the practical checks are focused validation scripts and compiler warning levels.

Run the nav-translation regression test:

```sh
cc -Wall -Wextra -I src tests/nav_translate_test.c src/nav_translate.c -o /tmp/nav_translate_test && /tmp/nav_translate_test
```

Run the profile checker against a firmware binary you own (this repo does not contain the protected `gal`/receiver binaries):

```sh
./tests/profile_check_test.sh /path/to/gal ...
```

The script compiles `tools/profile_check.c` and checks the profile table against the supplied firmware files.

### Requirements and environment notes

- Docker must be running before local builds.
- The build expects the QNX toolchain image name `qnx65-armv7-toolchain:8.5` (set via `QNX_IMAGE` if needed).
- The project is designed around QNX tooling and cross-compilation; do not assume normal host-only GCC or Node tooling is sufficient for the shipping binaries.

## Architecture and project flow

The big picture is easiest to understand as three layers:

1. Hook layer (`src/`)
   - Preloads into the Android Auto `gal` process.
   - Registers the second display and rewrites/filters the navigation messages that the stock receiver cannot handle.
   - Keeps the phone and cluster synchronized, and does the firmware-specific compatibility checks.

2. Player layer (`player/`)
   - Receives H.264 from the hook over loopback.
   - Decodes frames and draws them to the cluster display.
   - Switches the cluster to the map window when the stream is active and restores the stock map when it is not.

3. Installer/update layer (`scripts/`, `greenmenu/`, `swdl/`)
   - Packages the hook, player, and menu screens into an SD-card update.
   - Installs or uninstalls the custom map behavior on the car.
   - Exposes debug/status operations through the green engineering menu.

The `docs/Development.md` file is the canonical reference for why the design looks the way it does: the project was shaped around hardware limits, QNX-specific socket behavior, and unit-specific differences in the receiver and display manager. If a change affects the interop contract between the hook and player, read that document before patching.

## Key conventions and repository-specific patterns

- Keep PRs focused on one topic only. The project explicitly prefers a single firmware profile, fix, or doc change per pull request.
- Do not commit protected firmware binaries or vendor artifacts such as `gal`, `libautoreceiver*.so`, `libairplay.so`, `lsd.jxe`, or similar. Share them privately if a reviewer needs them.
- Shell scripts are expected to be compatible with QNX `ksh`; follow the existing style and avoid introducing dependencies the project explicitly avoids (`printf`, `cmp`, and `tr` are called out in `CONTRIBUTING.md` as things to avoid in the shell scripts).
- Comment the reason behind non-obvious shell or firmware work, and include the issue or bug reference when relevant.
- Firmware-specific changes usually touch multiple coordinates at once: the hook logic, profile metadata, and the supported-train list. For new cars or train support, update the relevant profile definition and the supported-train metadata together.
- Porting is a workflow, not just a code edit. The project’s contributor guidance expects an owner with a unit, a porting folder from the install flow, logs, and the tools in `docs/Development.md`/`tools/` to be used together.

## Useful references

- `README.md`: product overview, supported hardware, installation flow, and release expectations.
- `CONTRIBUTING.md`: contributor workflow, porting process, and project maintenance expectations.
- `docs/Development.md`: architecture, disassembly workflow, and firmware-porting details.
- `docs/Install.md`: operational install, recovery, and profile setup notes.

For this repo, the most important rule is: treat firmware compatibility as a constrained, evidence-driven problem, not a generic app feature. Validation usually means reproducing the right log/firmware behavior, and the right profile metadata must match the actual head-unit train.

## MCP servers

If you want, I can also configure relevant MCP servers for this project type, such as Playwright for web or a local firmware/log tooling setup.
