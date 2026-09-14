# mhi2-android-auto-video-vc

> Experimental native hook for Harman MHI2 GAL that projects Android Auto
> navigation video to the Volkswagen Virtual Cockpit.

## Acknowledgements — the foundations this project builds on

> This project would not exist without these projects and their maintainers.

- [VcMOSTRenderMqb](https://github.com/OneB1t/VcMOSTRenderMqb), by
  [OneB1t](https://github.com/OneB1t) — MOST150 and Tegra/OpenKODE
  rendering foundation.
- [MIB SDK](https://gitlab.com/andrewleech/mibsdk), by
  [Andrew Leech](https://github.com/andrewleech) — QNX cross-compilation
  environment.
- [MHI2_navignore](https://github.com/harman-f/MHI2_navignore), by
  [harman-f](https://github.com/harman-f) — HMI baseline.
- [mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc), by
  [Adrian Brennig](https://github.com/adi961) — companion HMI work.

This project is substantially more complex and time-consuming than initially
anticipated. It crosses private QNX/GAL internals, Android Auto negotiation,
H.264 transport, Tegra graphics, MOST150 routing, and Volkswagen Java HMI
state. A small change can require reverse engineering, offline validation, and
repeated in-car testing.

The long-form, reproducible development record is in the
[GitHub Wiki](https://github.com/chopinwong01/mhi2-android-auto-video-vc/wiki).

> [!CAUTION]
> **CRITICAL WARNING — EXPERIMENTAL, HIGH-RISK HEAD-UNIT MODIFICATION**
>
> This project injects code into a production QNX/GAL process and interacts
> with Android Auto protocol handling, Tegra graphics, DMDT/MOST routing, and
> the Volkswagen HMI. It is tested only on Volkswagen MIB2.5 High EU
> `MHI2_ER_VWG13_P4521_MU1367` (Harman MHI2, Tegra 30, QNX 6.5.0). It is not a
> compatibility promise for another firmware, VAG brand, i.MX6/MHI2Q unit, or
> non-Virtual-Cockpit vehicle.
>
> An incorrect firmware match, ABI assumption, installation, configuration,
> supervisor environment, or companion-JAR build can crash GAL, create restart
> loops, or leave the infotainment UI unavailable. Recovery can require the
> verified stock package, a controlled reboot, or bench/serial access. Do not
> install or test this while driving. Keep backups and a verified rollback path
> before deployment; never modify `/lib` or `/usr/lib`.
>
> AI-assisted code and documentation are not a safety guarantee. Treat every
> generated claim as an untrusted hypothesis and validate it against the target
> binary, logs, and physical vehicle behavior.

## What it does

Stock GAL owns one primary Android Auto video sink and one shared center-display
renderer. This project injects a secondary sink, keeps its playback away from
that shared renderer, forwards the secondary H.264 stream to `stream-player`,
and routes the player's OpenKODE output to the Cockpit.

```text
Android phone ── AAP over USB ──► gal + libgal_hook.so
                                       │
                                       ├─ secondary service and H.264 extraction
                                       ▼
                            TCP 127.0.0.1:12346
                                       ▼
                                stream-player
                                       │ glDrawTextureNV / EGL
                                       ▼
                    DMDT: display 4 → context 70 → Displayable 3
                                       ▼
                           MOST150 Virtual Cockpit
```

## Runtime model

1. `libgal_hook.so` is injected into GAL with `LD_PRELOAD` and dynamically
   registers a secondary video endpoint.
2. Android Auto opens the secondary service. The hook withholds secondary
   playback from GAL's single shared renderer, preserving the center display.
3. Secondary Annex-B H.264 is sent over TCP loopback to `stream-player`.
   SPS/PPS and one bounded IDR are cached so a newly connected player has
   decoder bootstrap data before delta frames.
4. `stream-player` decodes with FFmpeg and presents through Tegra's
   `GL_NV_draw_texture`, avoiding the unavailable online shader compiler.
5. When the Kombi route is ready, DMDT maps Displayable 3 into Cockpit context
   70 using display ID 4. On teardown, displayable 33 is restored.

The normal output mode is `withhold`. Sending secondary `playbackStart` through
stock GAL's shared renderer is diagnostic-only and can blank or reconfigure the
center display.

### ACK behavior

The player writes a byte to `/tmp/gal_ack.sock` after presentation. While that
feedback channel is healthy, the hook turns player ACKs into phone-frame ACKs.
If no player has connected, or no feedback arrives for more than 500 ms while
frames continue, the hook fails open and ACKs immediately so a player fault does
not also terminate the phone session. A live Android Auto session therefore
does not by itself prove that the player is rendering.

## Verified constraints

| Item | Current assumption |
|---|---|
| Head unit | Harman MIB2.5 High / Tegra 30 |
| Firmware | `MHI2_ER_VWG13_P4521_MU1367` |
| Coded Cockpit video | Fixed 800×480; 30 or 60 FPS accepted by the hook |
| Normal advertised rate | 30 FPS |
| Cockpit DMDT route | Display ID 4, context 70, player displayable 3 |
| Stock restoration | Displayable 33 in context 70 |
| Stream transport | TCP loopback; default port 12346 |

Do not substitute the index printed by `dmdt gs` for DMDT display ID 4. The
wrong value can be accepted without changing the visible route.

## Configuration

Copy [`scripts/gal_dualscreen.conf.example`](scripts/gal_dualscreen.conf.example)
to the SD-card root as `gal_dualscreen.conf`. The file avoids the supervisor's
small environment budget and can be changed between boots. Values injected by
`enable_hook.sh` take precedence over file values.

Important settings:

| Key | Usual value | Purpose |
|---|---|---|
| `GAL_DUALSCREEN_OUTPUT` | `withhold` | Keep secondary video out of stock GAL renderer. |
| `GAL_STREAM_ENABLE` | `1` | Forward H.264 to `stream-player`. |
| `GAL_STREAM_PORT` | `12346` | TCP loopback listener. |
| `GAL_DUALSCREEN_AAP_MINOR` | `7` | Advertised AAP minor for two-display testing. |
| `GAL_DUALSCREEN_CLUSTER_INPUT` | `1` | Advertise the cluster input service. |
| `GAL_VC_DISPLAYABLE_ID` | `3` | Player displayable. |
| `GAL_VC_CONTEXT` / `GAL_VC_DISPLAY` | `70` / `4` | Cockpit DMDT route. |

The canvas is always 800×480. `GAL_SECONDARY_DPI` is a UI scale hint, not the
panel's physical DPI. Insets use `top,bottom,left,right`; if
`GAL_SECONDARY_UI_CONFIG_HEX` is set, its exact protobuf bytes override scalar
inset/theme settings. Change one geometry or protocol value per test.

## Build

Prerequisites: Docker and access to the MIB SDK image. `player/Makefile`
cross-compiles its own FFmpeg-mini (static libavcodec/libavformat/libavutil
for QNX 6.5.0 ARMv7) via `player/build_ffmpeg.sh` the first time it's
needed, caching it under `player/build/`.

```sh
docker pull registry.gitlab.com/andrewleech/mibsdk:latest
make hook
(cd player && make)
```

This produces `libgal_hook.so`, `lib/libdmdt_flush.so`, and
`player/stream-player`. Verify that release artifacts target QNX ARM; a
successful host build does not validate the GAL ABI, phone negotiation, DMDT
route, or Cockpit output.

## Install and validate

> [!WARNING]
> `smartphone_integrator` has an approximately ten-entry `envs` limit. Exceeding
> it can silently discard the entire environment array, including `LD_PRELOAD`.

Prepare the SD-card package: `libgal_hook.so`, `stream-player`, `config.txt`,
`enable_hook.sh`, `disable_hook.sh` and a reviewed `gal_dualscreen.conf` in the
card root, `libdmdt_flush.so` in `lib/`, and `hook_status.sh` and
`lib_app_mount.sh` in `scripts/`. The installer copies both libraries under
`/mnt/app/eso/lib`; see
[where the libraries go](wiki/Installation-and-Safety-Guide.md#where-the-libraries-go).
On the unit:

```sh
cd /fs/sdb0
sh ./enable_hook.sh
sh ./scripts/hook_status.sh
```

Reboot the unit, then test all of the following independently:

1. Android Auto starts on the center display.
2. The Cockpit receives the intended map/video.
3. Android Auto's in-app Exit returns the center display to App-Connect while
   the phone session and Cockpit navigation remain active.
4. Re-entering Android Auto restores center video.
5. App-Connect Disconnect tears down both paths.
6. A subsequent reboot reaches the normal stock UI.

`hook_status.sh` proves logged internal stages, not correct visual output. Save
the complete hook and player logs, firmware identity, package revision, config,
injected environment values, phone model, and Android Auto version for each
test. Record failures as carefully as successes.

To roll back, run the matching `disable_hook.sh` from the SD-card package. It
restores the saved supervisor configuration, removes the preload payload, and
attempts to restore the Cockpit route. Inspect the route if DMDT restoration
reports a failure.

## Java HMI integration

The native renderer is separate from the Volkswagen Java HMI layer:

- [`MHI2_navignore`](https://github.com/harman-f/MHI2_navignore) is the baseline
  patch commonly used to relax stock navigation mutual exclusion.
- [`mib2-android-auto-vc`](https://github.com/adi961/mib2-android-auto-vc)
  supplies optional steering-wheel zoom, D-pad routing, and banner behavior.

In-app Exit is an HMI state transition, not merely a renderer stop or DMDT
command. Primary focus must retain the stock HMI route; secondary focus must not
overwrite the global LSD focus state. Treat every HMI/JAR change as a separate,
high-risk test boundary. The target IBM J9 VM also requires the established
legacy Java build compatibility; a host-valid modern JAR can fail verification
on the unit.

## Repository layout

```text
src/        GAL hook, secondary-sink handling, stream transport, player manager
player/     FFmpeg/OpenKODE Cockpit renderer
dmdt_flush/ _exit() interposer that lets the player read dmdt output via popen
scripts/    configuration template, installation, rollback, diagnostics, deploy
```

## Roadmap

- Make secondary focus and Cockpit-tab behavior explicit and road-validated.
- Consider AF_UNIX only after descriptor inheritance and socket ownership are
  solved; it is not a mechanical performance change.
- Investigate hardware decode only with reproducible car evidence.
- Keep GPS uncertainty experiments out of production until road-validated.

## Acknowledgments

- The related projects above, FFmpeg, and the MIB2/MQB community.
- AI-assisted development: OpenAI Codex/GPT, Anthropic Claude, Google Gemini,
  and Google Antigravity assisted research, implementation, and documentation.
  The maintainer remains responsible for the released code and validation.

## License

[GNU General Public License v3.0](LICENSE).
