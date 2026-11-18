# Development

How it works, what was learned, how to add a firmware, and how to build.
The upstream project, [chopinwong01/mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc),
keeps the original design notes and development story.

## How it works

```text
phone ──USB──► gal (stock Android Auto program)
                 └─ libgal_hook.so: adds a second display, forwards its H.264
                      │  TCP 127.0.0.1:12346
                      ▼
               stream-player: decodes, draws into displayable 3
                      │  display manager: context 70 on display 4
                      ▼
               the unit's hardware encoder ──MOST150──► cluster
```

1. **The hook** (`src/`) is preloaded into `gal` through
   `smartphone_integrator.json`. It registers a second video sink, so the
   phone offers its cluster display, and sends that display's video to the
   player. It depends on the exact layout of `gal`, which is why each
   firmware needs a profile (`src/firmware_profiles.h`). On a build it does not
   recognise, it does nothing.
2. **The player** (`player/opengl_gpu.cc`) decodes the video, either with the
   unit's NvSS hardware decoder (`libnvss_video.so`, the one `gal` uses for
   the centre screen) or FFmpeg in software drawn with `glDrawTextureNV`.
   Standard 800×480 remains the default; optional 1280×720 and 1920×1080
   modes crop margins to the cockpit window, using nearest luma sampling for
   exact 1:1 pixels. NvSS output 1 is Audi-only (Skoda reports `0x0`); the
   Audi 1080p configuration is documented in [Install](Install.md). At
   the first keyframe it switches the cluster to its window
   (`dmdt dc 70 3`, `dmdt sc 4 70`); at the end it gives the stock map back
   (`dmdt dc 70 33`).
3. **The unit** encodes that window and sends it to the cluster as it does
   the built-in map.

Installer, menu and update scripts are in `scripts/`, `greenmenu/` and
`swdl/`. `tools/` holds the profile finder and the update metadata builder.

## What was learned

These shaped the design; changing them has broken things before.

- **Pace the phone with the display.** The hook holds back each frame's
  acknowledgement until the player has shown it (one byte on
  `/tmp/gal_ack.sock`). Acknowledging on arrival lets the phone raise its
  bitrate past what the unit can show: buffers overflow, keyframes drop, the
  picture breaks into green blocks.
- **No frame-parallel decoding.** FFmpeg frame threading holds each frame
  until the next packet arrives, while the phone waits for the
  acknowledgement before sending it: a deadlock that ends at the phone's
  ~300 ms timeout, so 3.3 fps. The player uses low-delay, slice threading.
- **TCP, not a Unix socket.** On QNX 6.5 a Unix socket has a fixed 5 KB
  buffer that `setsockopt` ignores; a 140 KB keyframe needs 27 round trips and
  the stream falls to 3–4 fps. TCP loopback takes 2 MB buffers.
- **Grant video focus only when the player is ready.** The hook keeps the
  second sink unfocused until the player is connected and the cluster map is
  up, so the phone starts with a fresh keyframe.
- **Keep the centre renderer out of it.** `gal` has one shared renderer;
  routing the second display through it can blank the centre screen.
- **Ten environment entries at most.** `smartphone_integrator.json` drops a
  child's whole `envs` list if it has more than ten. The installer checks.
- **No online shader compiler.** The unit's GLES2 has
  `GL_SHADER_COMPILER == 0`, hence `glDrawTextureNV`.
- **Java patches need an IBM Java 1.2-level compiler.** The interface runs on
  IBM J9; classes from a modern `javac` fail verification and the centre
  screen does not start.
- **The turn-arrows jar breaks the map.** With `VCAndroidAuto.jar` loaded, the
  cluster map goes blank when a route starts, so the installer removes it for
  the map. NavActiveIgnore is needed so a phone route does not end the
  cluster map.

## Settled parts

Since v1.2.0 the default path has not changed: how the hook announces the
second display, how the player decodes and draws, and how the installer puts
them on the unit. From v1.2.6 these are treated as settled. Releases from
v1.2.1 to v1.2.6 changed car lists, per-car options, installer edge cases and
diagnostics.

**What is settled**

| Part | Files |
|---|---|
| Hook: second display, focus, acknowledgements | `src/` |
| Player: decode, draw, cockpit switch and restore | `player/opengl_gpu.cc` |
| Installer and uninstaller | `scripts/enable_hook.sh`, `scripts/disable_hook.sh`, `scripts/lib_*.sh` |
| Green menu | `greenmenu/` |

**What stays open without ceremony:** a line in `config/profiles.conf`, the
tested-values table in `docs/Install.md`, the README, log collectors, and new
log lines that change no behaviour.

**A change to a settled part needs one of these**

1. A fault on a car that is listed as working, shown in a log.
2. A new car that can't be served by a `profiles.conf` word or an existing
   setting.
3. A feature. It ships off, behind a setting or a `profiles.conf` word, and
   with it off the unit must do what it did before. It is switched on for a
   car only after a log from that car.

And every such change:

- names the report it answers in the commit;
- passes `./build_local.sh simtest` when it touches any script the unit runs:
  the install in the unit's own shell version, on every train we hold files
  for (docs/Testing.md). A bench in dash, ksh93 or bash does not count: they
  pass what the unit's shell stops on (docs/Unit-shell.md);
- passes `tests/regression_guards.sh`, `tests/profile_check_test.sh`,
  `tools/check_scripts.py` and `tools/unit_shell_lint.py` (the build refuses
  to pack a card otherwise);
- says in the release notes whether it has run on a car;
- adds a guard to `tests/regression_guards.sh` when it fixes a fault that
  reached a release.

A pull request tested on one car is taken as an opt-in setting, not as a new
default.

**Faults that reached a release, and what guards them now**

| Release | Fault | Cause | Guard |
|---|---|---|---|
| v1.2.0 | installer stopped part-way | the bench ran without `set -eu`; the unit runs with it | bench rule above; guard 3 |
| v1.2.2 | broken picture | NEON routines read unaligned data, which this processor set-up faults on | `tools/neon_audit.py` |
| up to v1.2.4 | green menu "script not found" after an install from USB or SD slot 2 (#109) | `/fs/sda0` baked into paths | guard 2, `tests/sda0.allow` |
| up to v1.2.5 | `GAL_DUALSCREEN_ENABLE=0` did nothing (#101) | the installer wrote a fixed `=1` into gal's start-up, and the start-up value beats the settings file. Since v1.2.7 the settings file decides this one key in the hook as well, so the menu's Cluster map OFF/ON counts | guard 1 |
| test builds of v1.2.7 (not released) | install stopped after "Cluster map window" | a block ended in `[ test ] && echo`, which only the unit's shell stops on under `set -e`; the fourth time | `tools/unit_shell_lint.py`, `tests/unit_sim` |
| test builds of v1.2.7 (not released) | a new arrows jar never reached the unit (#24) | the installer copied a jar only when none was loaded | `tests/unit_sim` step 3; `tests/lsd_jar_test.sh` |
| a pull request, caught in review | picture crop on for every car (#85) | a one-car change made the default | guard 4; the opt-in rule |

The pattern in the last three: a value or a path that was right on the test
car was written as a constant. When fixing one, search for every other place
the same constant is written.

## Open core work

Four things are not settled. Each has a test that has to pass on a car before
it becomes a default or is listed as supported.

| Work | State | Test that settles it |
|---|---|---|
| The unit takes the cockpit back while the player draws (#105, #24) | cause unknown. v1.2.6 logs it (`context:` lines, `context_check.txt`) and has `GAL_PLAYER_REASSERT=1`, off | 1. A Save logs from an affected car on v1.2.6: the `context:` line gives the time, and the system log around that time should name what switched it. 2. The same car with `GAL_PLAYER_REASSERT=1` for a drive: map stays, at most a few re-asserts, no flicker. 3. A car without the fault (the Golf) with the setting on: no re-assert logged. Default only after 2 on two cars and 3. |
| CarPlay on the 857727 library (`P3301`, Audi A4 and A6) | no build. One file serves VW and Audi (same SHA-256, #104) | Static first: the same offsets audit as for 857735, against the file we hold. Then behind `CLUSTERMAP_CARPLAY_TRIAL` on one VW and one Audi, each with an uninstall card ready: CarPlay still connects on the centre screen, the cockpit shows the map, a route starts and ends. An Audi result does not follow from a VW one (#14). |
| Cars with one display for everything (Audi TT `P5098`, #99) | hook verified, phone opens the second display, no window 33 to draw in | The `dmdt gd` and `dmdt gc` sections of Collect in both map views, to find the window and context the stock map uses. Then a trial build that targets it, on that car only, with the uninstall card ready. |
| 720p and 1080p frame modes (pull request #125); hardware decode on VW | off by default. 720p in software: 30 pictures a second on a Golf at a third more CPU, no gain on 800x480. 1080p in software: 15. 1080p with the hardware decoder: one Audi A3 | 720p on a cockpit window larger than 800x480 (1010x376 or 1280x480) with `GAL_PLAYER_STATS=1`: a steady 30 and a photo against the normal mode. The installer ignores both modes on an 800x480 window. Hardware decode on VW goes through the unit's plain decoder (`libnvmedia.so`, into memory), since the cockpit is not a display output there: done and run on a Golf `P4521` (30 pictures a second, about 35 % of a core against 100 % in software, beside the centre screen's decoder and through a wireless adapter). The default on `P4521` since v1.2.7 (`hwdecode` word; `GAL_PLAYER_DECODER=auto` is `sw` on every other train). For another train: a `usable` from the green menu's **Hardware decoder check** (`tools/nvprobe`, which compares every picture with a reference decode) and one real drive with `hw`, then a `profiles.conf` word makes it that train's default. |

For each: one change per run, the tester gets exact steps and the way back,
and the log decides, not the photo alone.

### The connection loop

Once the unit claims Android Auto 1.6 or later (`GAL_DUALSCREEN_AAP_MINOR`
6 or 7), Google Maps stops sending the old
next-turn messages (`0x8004`, `0x8005`) on the navigation service and sends
`0x8006` (NavigationState) and `0x8007` (NavigationCurrentPosition) about once
a second instead. The 2018 receiver does not know them and replies "unexpected
message"; the phone treats that as a protocol error and resets the link, every
~17 seconds. The hook interposes `MessageRouter::sendUnexpectedMessage` and
drops that reply while the cluster sink is registered
(`GAL_FIX_SUPPRESS_UNEXPECTED`, on). The navigation service id is assigned at
start-up (12 here); read it from the `event=service.class` log line.

The newer messages are not translated, so at 1.6 and later the Java side
gets no turn data. Up to 1.5 the phone still sends the old pair and the
arrows jar's pictograms work, with the map shown at every version from 1.2
to 1.7 (#4: SEAT `P4709`, 2 to 5 work, 6 does not). The shipped settings
therefore claim 1.5.
`kamgurgul/mib2q-carplay` rewrites `0x8006`→`0x8004` and `0x8007`→`0x8005`
before `gal` routes them; porting that is the place to start for both at once.

### Zoom

No input was found that makes the phone zoom the map it draws for the
cluster. Rotary, D-pad and zoom keys on the cluster input channel do nothing
(the phone binds only the keys advertised: 23 and 65536); rotary on the main
channel moves a highlight on the centre screen; pinching the centre map does
not move the cluster map. kamgurgul found the same on Audi, and Google
describes cluster displays as non-interactive. The test harness is
`GAL_INPUT_INJECT=1` with `scripts/experiments/zoom_test.sh`. A local
crop-and-enlarge in the player is possible but was not built.

## Adding a firmware

Two people are usually involved: an owner with the car, who collects the
files ([Install guide](Install.md#getting-your-unit-added)), and a porter who
can read ARM disassembly.

1. **Propose a profile:**

   ```sh
   pip install capstone
   python3 tools/find_profile.py porting_X/gal porting_X/libautoreceiver.so MHI2_ER_XXXXX_Pxxxx
   ```

   It prints the three fingerprint addresses (exact), the handler constructor
   and its call site (a proposal), a comparison of the receiver library with
   P4521's, and a table entry plus a `GAL_PROFILE_TRIAL=` line. It stops
   without a proposal if a fingerprint symbol is missing or there is not
   exactly one call site.
2. **Check what the tool cannot see,** with `tools/armre.py <file> dis <symbol-or-0xaddress>`:

   | Field | Confirm |
   |---|---|
   | `ctor`, `handler_size` | `operator new(size)` then the constructor, which stores vtable pointers inside `_ZTVN3gal25CVideoSinkCallbackHandlerE` (five on P4521) |
   | `ctl_config_off`, `ctl_creator_off` | the 2nd and 4th call arguments are `controller + offset`: the configuration source and the renderer-creator pointer |
   | `h_cfg_count_off`, `h_cfg_data_off`, `cfg_entry_size` | the handler's entry count and array of entries starting with resolution and frame rate. The tool reads them from the constructor's copy of the table (`add REG, r4, #X`, the three words at X cleared, `mov r0, REG`); they differ between generations: +0x80/+0x84 on P4521, +0x78/+0x7c on VWG11 |
   | `settings_first`, `settings_last`, `stock_displayable` | the renderer settings block copied into the handler; the stock window id (59 on VW) may be in it (not derived) |
   | the receiver library | if not byte-identical to P4521's (`b04cb5cf…`) or VWG11 K3342's `libautoreceiver_qnx.so.1` (`c4b06d69…`), re-check the hook's object offsets in it: endpoint open flag/channel (+4/+5), router (+8), service id (+12), the VideoSink vtable slots, sink session (+0x18), codec (+0x14), max unacked (+0x1c), configuration vector (+0x40/+0x44, 8-byte entries), and the message offsets in `receiver_layout` (`src/video_sink_hook.c`) |

   The hook knows two receiver generations. P4521's protobuf messages have an
   unknown-field string at +0x08, and the hook writes the fields gal's schema
   lacks (display id and type, UiConfig, the cluster input service) into it.
   VWG11's older receiver has a five-argument `addSupportedConfiguration` and
   no unknown-field strings, so the hook adds the same bytes to the encoded
   service discovery response in `MessageRouter::queueOutgoing` instead; the
   log line is `discovery.rewrite`. A receiver that has the seven-argument
   function is treated as P4521's, the five-argument one as VWG11's.

   Also compare the cluster values in `info.txt` with P4521's: stock map
   window 33, context 70, display 4. The player has these fixed today; a unit
   with different values needs them made configurable.
3. **Trial without a rebuild:** put the `GAL_PROFILE_TRIAL=` line in
   `ClusterMap/gal_dualscreen.conf` and install from the green menu, the
   software update or SSH. The installer accepts an untested train only when
   a trial line names it. A trial is used only if its fingerprints match the running `gal`,
   and the hook checks the constructor's first instruction before each use.
   In the log: `firmware.trial result=selected`, then
   `secondary.video_config result=success`, `secondary.register result=success`
   and `aap.frame.framing ... annex_b=yes`. A wrong profile can crash `gal`,
   which the unit restarts; nothing else is touched.
4. **Make it permanent:** this is data, not code. Add one line to
   `config/profiles.conf` with TESTED 0, and open a pull request with the tool
   output and log lines. TESTED becomes 1 after a drive: map up, route started,
   phone unplugged and replugged. Then add a `train` line with `map`, plus
   `navignore` or `arrows` once owners have shown those work. The hook, the
   installer and `profile_check` all read this one file; nothing is rebuilt. A
   train whose `gal` matches an existing profile needs no change to install,
   only a `train` line to be listed as tested.

The turn-arrows jar is a separate port: it replaces Java classes of the
unit's interface and has to be rebuilt against that firmware's `lsd.jxe`
(the 55 MB collect entry copies it) in
[our fork](https://github.com/MacsInSpace/mib2-android-auto-vc) of
[adi961's project](https://github.com/adi961/mib2-android-auto-vc), which
adi961 no longer maintains. Its README lists our changes; the bundled jar is
the fork's release, built against `P4521` and car-tested there. adi961's
builds worked on the other `arrows` trains in `config/profiles.conf`; the fork's changes
still need a test on those. Keep the unit's `lsd.jxe` out of git: it is
firmware.

## Building

Needs Docker. On Apple Silicon the toolchain runs under emulation and the
first build takes 30–60 minutes.

```sh
git clone https://github.com/luka-dev/qnx65-armv7-toolchain
cd qnx65-armv7-toolchain && ./host-scripts/qnx-run.sh build 8.5
# if ftp.gnu.org refuses connections, use https://mirrors.kernel.org/gnu/ in
# the Dockerfile (the checksums are pinned)

cd ../mib-cluster-map
./build_local.sh            # hook, helper, FFmpeg, player, dist/sdcard and the release zip
./build_local.sh player     # only the player; also: hook, package
```

FFmpeg 6.1.5 is downloaded, checked and built on first use.

## Testing on a car

Run everything in docs/Testing.md first.

Change one thing per run, and record the firmware, the package build
(`SHA256SUMS.txt`), the settings file, the hook and player logs, and the phone
and app versions. Save logs before rebooting. A result from one car is a
result for that car and firmware; say so when reporting it.

## Android Auto 1.6+ navigation

From protocol 1.6 Google Maps replaces `0x8004`/`0x8005` (next turn,
distance) with `0x8006 NavigationState` and `0x8007 NavigationCurrentPosition`.
This unit's receiver was built against 1.2 and rejects them, which is why the
turn pictograms stopped at `GAL_DUALSCREEN_AAP_MINOR=6` (#4).
`src/nav_translate.c` decodes the new pair in `routeMessage` and writes the old
one over it, in place, so the stock endpoint and the arrows jar see what they
always did. It also maps the new status 3 (rerouting) to 1 (active). The 1.7
schema and manoeuvre table come from
[kkrvch/mib-std2-kombibridge](https://github.com/kkrvch/mib-std2-kombibridge)
(its author invited reuse in that project's issue #5, and lito69 pointed us
to it in #4: thank you both); the legacy field numbers
are this receiver's own `k*FieldNumber` symbols. Host test:

```sh
cc -I src tests/nav_translate_test.c src/nav_translate.c -o /tmp/navtest && /tmp/navtest
```

Lanes and the distance and time to the destination are decoded by kombibridge
but have no field in the old messages. Showing them on the cockpit needs the
Java side (its `LaneGuidance`, `DistanceToDestination` and `TimeToDestination`
BAP functions), which is not part of this project yet.
