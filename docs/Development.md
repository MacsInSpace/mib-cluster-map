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
   the centre screen) or FFmpeg in software drawn with `glDrawTextureNV`. At
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

### The connection loop

Once the unit offers a cluster display, Google Maps stops sending the old
next-turn messages (`0x8004`, `0x8005`) on the navigation service and sends
`0x8006` (NavigationState) and `0x8007` (NavigationCurrentPosition) about once
a second instead. The 2018 receiver does not know them and replies "unexpected
message"; the phone treats that as a protocol error and resets the link, every
~17 seconds. The hook interposes `MessageRouter::sendUnexpectedMessage` and
drops that reply while the cluster sink is registered
(`GAL_FIX_SUPPRESS_UNEXPECTED`, on). The navigation service id is assigned at
start-up (12 here); read it from the `event=service.class` log line.

The newer messages are not translated, so the Java side gets no turn data;
that is one reason the arrows and the map cannot run together.
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
4. **Make it permanent:** add the entry to `k_profiles[]` with
   `car_tested = 0`, the train to `SUPPORTED_TRAINS` in
   `greenmenu/GEM/common.sh`, and open a pull request with the tool output and
   log lines. It becomes `car_tested = 1` after a drive: map up, route
   started, phone unplugged and replugged.

The turn-arrows jar is a separate port: it replaces Java classes of the
unit's interface and has to be rebuilt against that firmware's `lsd.jxe`
(the 55 MB collect entry copies it) in
[our fork](https://github.com/MacsInSpace/mib2-android-auto-vc) of
[adi961's project](https://github.com/adi961/mib2-android-auto-vc), which
adi961 no longer maintains. Its README lists our changes; the bundled jar is
the fork's release, built against `P4521` and car-tested there. adi961's
builds worked on the other `TBT_TRAINS` in `common.sh`; the fork's changes
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

Change one thing per run, and record the firmware, the package build
(`SHA256SUMS.txt`), the settings file, the hook and player logs, and the phone
and app versions. Save logs before rebooting. A result from one car is a
result for that car and firmware; say so when reporting it.
