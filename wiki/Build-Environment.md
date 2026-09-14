# Build Environment

## Prerequisites

- Docker capable of running the MIB SDK image.
- Access to `registry.gitlab.com/andrewleech/mibsdk:latest`.
- Network access the first time you build `player/`, so
  `player/build_ffmpeg.sh` can fetch FFmpeg sources; the resulting
  ffmpeg-mini static libs are cached under `player/build/` afterwards.
- A clear deployment plan; never substitute host libraries for QNX libraries.

```sh
docker pull registry.gitlab.com/andrewleech/mibsdk:latest
make hook
(cd player && make)
```

`make hook` builds `libgal_hook.so` and `lib/libdmdt_flush.so` through the QNX
ARM toolchain in Docker. The root Makefile provides `all`, `hook`, `shell`, and
`clean`; it does not create a release package. If deployment expects
`dist/sdcard_hook`, assemble that package through the corresponding packaging
workflow before invoking the remote deployment helper.

## Expected artifacts

| Artifact | Source | Role |
|---|---|---|
| `libgal_hook.so` | `make hook` | GAL preload hook. |
| `lib/libdmdt_flush.so` | `make hook` | `_exit()` interposer that makes `dmdt` flush its output, so the player can read `dmdt gs` through a pipe. Goes in the package's `lib/`; see [where the libraries go](Installation-and-Safety-Guide.md#where-the-libraries-go). |
| `player/stream-player` | `player/Makefile` | FFmpeg/OpenKODE cluster renderer. |
| `player/build/ffmpeg-mini/` | `player/build_ffmpeg.sh` (auto-run by `player/Makefile`) | Static libavcodec/libavformat/libavutil for QNX ARMv7. |
| `player/config.txt` | Repository | Player defaults and stream URL. |
| `scripts/*.sh` | Repository | Install, rollback, diagnostics, deployment helpers. |
| `gal_dualscreen.conf` | Derived from example | Runtime configuration outside the supervisor budget. |

## Build and package checks

Verify the results are QNX ARM artifacts, inspect dependencies in the SDK
environment, and keep the hook and player from the same source revision. A
host-side build does not validate the target GAL ABI, DMDT routing, or Android
Auto discovery.

Use `scripts/gal_dualscreen.conf.example` as the complete configuration
reference. File configuration exists because `smartphone_integrator` has an
approximately ten-entry environment limit. Values injected by `enable_hook.sh`
override file values; record both when reproducing a test.

## Remote deployment helper

`scripts/deploy_to_car.sh [IP] [--with-jars]` requires an existing
`dist/sdcard_hook` directory. It stops running GAL/player processes, copies the
package to `/fs/sdb0`, invokes `enable_hook.sh`, and requires a later reboot.
It skips JAR updates unless `--with-jars` is supplied. It is a development
convenience, not evidence that a package is safe for another firmware train.
