# CarPlay and Android Auto on the same unit

Goal: one package that puts the phone's map on the cluster for **both** phone
types. Only one phone projects at a time, so the two never need the cluster at
once; they only have to stop getting in each other's way.

The CarPlay side is [CarPlay Maps VC](https://github.com/omonob/MHI2-Carplay-Maps)
by omonob (GPL-3.0; fork at
[MacsInSpace/MHI2-Carplay-Maps](https://github.com/MacsInSpace/MHI2-Carplay-Maps)),
installed with its own installer, unchanged.

Status: **branch `carplay`, not released, not yet run on a car.**

## How each one reaches the cluster

| | Android Auto map (this project) | CarPlay map (CarPlay Maps VC) |
| --- | --- | --- |
| Hooked process | `gal`, via `smartphone_integrator.json` | `dio_manager`, replaced by a wrapper script |
| Video path | phone H.264 → decoded on the unit (`stream-player`) → display-manager window (context 70) → the unit's own encoder → MOST → cluster | phone H.264 → `altscreen-most-bridge` → straight onto the MOST video channel (`/dev/mlb/isoTX2`) → cluster |
| When it takes the cluster | while Android Auto sends cluster video | `carplay-cluster-supervisor` starts the bridge only when a CarPlay map stream is ready, and hands the channel back to the stock map after |
| Java patch | `NavActiveIgnore.jar` | `CarPlayNavigationPatch.jar` (the same nine classes, byte-identical), plus `CarPlayClusterControls.jar` (steering-wheel zoom) |
| Firmware check | `gal` addresses (profile table) | size of `/ifs/lsd.jxe`: MU1102, MU1367, MU1440 |
| Cluster choice | none needed | 790 (10.25 in) or 791/794 (12.3 in), chosen at install |

Each one changes a different system file, except `lsd.sh`. Neither touches the
other's video path.

### Display manager or direct link?

**How the stock unit does it.** The cluster only ever gets video from the
head unit. The unit draws the cluster map into a display-manager context.
Its Tegra hardware encoder (NvMedia) turns that into H.264, which goes over
MOST150 to the Active Info Display, and the display decodes it. The cluster's
decoder is matched to the unit's own encoder output.

**The display-manager route** (this project, and every Audi project with
published source: luka-dev/mib2q-carplay-rgi and kamgurgul/mib2q-carplay on
MHI2Q, aberbic's Tegra MHI2 project for CarPlay *and* Android Auto). The
phone's video is decoded on the unit and drawn into a cluster context, and
the stock encoder does the rest. The cluster sees the same kind of stream it
always gets, and handing back to the stock map is the unit's job. The cost is
decoding on the head unit. Our player does that in software (FFmpeg, 60-120 %
of a core). aberbic's renderer uses the unit's hardware decoder
(`libnvss_video.so`, the one `gal` uses for the centre screen). kamgurgul's
did the same on MHI2Q and went from about 24 ms to about 3 ms per frame.

**The direct link** (omonob's CarPlay Maps VC, and harman-f/mhi2_altscreen_carplay,
whose source is published) skips decoding and encoding on the unit. The phone's
H.264 is repackaged as MPEG-TS and written straight to the MOST channel
(`/dev/mlb/isoTX2`). That saves processor time, but the cluster then has to
decode a stream it was never tuned for. On a Golf 7.5 with MU1367 and the
12.3-inch 791 cockpit, owners report lag and coloured blocks (omonob issue
#10). Their logs show the queue overflowing on bitrate peaks, and omonob
blames the cluster's decoder chip. harman-f proved the direct link on the
10-inch Skoda cockpit and warns that the 12.3-inch family is not proven.

**Conclusion.** Keep the display-manager route for both phones, and add the
hardware decoder to `stream-player`. A CarPlay capture hook with published
source (harman-f's, also used by aberbic) could then feed the same player,
giving one renderer for both phones with no binaries lacking source. Keeping
CarPlay Maps VC separate also works for testing.

### Step one: the hardware decoder (done, not yet car-tested)

`stream-player` can now decode on the unit's own NvSS decoder
(`GAL_PLAYER_DECODER=hw`, the default on this branch). It calls
`libnvss_video.so` the same way `gal` does for the centre screen. The calls
and structures were checked by disassembling the MU1367 `gal`, and they match
aberbic's MU1438 layout. The decoder draws straight onto displayable 3, so
there is no OpenGL and no software decode. If it will not open, the player
uses FFmpeg as before. If it fails while decoding, it switches itself off
until the next reboot. `sw` restores the v1.0.0 behaviour exactly.

This is the part a CarPlay capture would also need, so it gets tested on its
own first, with Android Auto.

## One installer for every unit

The software update and the menu install now pick what fits the unit:

| Unit | What gets installed |
|---|---|
| A train with a cluster-map profile (VW P4521, K4525) | the cluster map |
| A train where the turn-arrows jar is known to work (SEAT P4708, P4709) | the turn arrows |
| Anything else, including Audi MHI2Q and MIB2 Standard | nothing, with a pointer to the right project |

The CarPlay map is a separate menu entry for now, because it needs the
cockpit size (790 or 791) and the CarPlay Maps VC files on the card.

## Where they collided, and what changed here

1. **Merged Java patch lines.** CarPlay Maps VC adds its jars to the *first*
   existing `-Xbootclasspath/p:` line rather than adding a line. Afterwards
   the line looks like
   `...p:$BASE_DIR/lsd/jars/CarPlayClusterControls.jar:$BASE_DIR/lsd/jars/NavActiveIgnore.jar"`.
   `lsd_jar.sh` used to delete whole lines, so removing NavActiveIgnore (or
   the turn-arrows jar) would have taken CarPlay's jar with it. It now finds
   and removes a jar as one entry of a line. Lines that are commented out are
   ignored.
2. **One navigation patch, two names.** Their installer keeps an existing
   NavActiveIgnore instead of adding its copy. The Android Auto installer now
   counts `CarPlayNavigationPatch.jar` as NavActiveIgnore too. The Android
   Auto uninstall leaves NavActiveIgnore in place while CarPlay is installed
   and depends on it.
3. **Their restore puts back a whole `lsd.sh` copy** taken when CarPlay was
   installed, which undoes any later Java-patch change. The CarPlay uninstall
   in this package (`carplay.sh uninstall`) does the same restore piece by
   piece instead: the stock `dio_manager`, their two jar entries, their jar
   files, and their folder. With CarPlay installed alone, install then
   uninstall returns `lsd.sh` to stock byte for byte.

Sandbox checks, using their real installer in its test-root mode against a
real MU1367 `lsd.sh`:
- Android Auto map first, then CarPlay.
- CarPlay first, then the Android Auto map.
- Removing the turn arrows with CarPlay installed.
- The CarPlay uninstall.
- `lsd_jar.sh` still reproduces the toolbox's output byte for byte.

## Licence note

CarPlay Maps VC is GPL-3.0. Its repository holds the install scripts and some
Java sources, but **not the source of its native programs**: `core.so`,
`altscreen-most-bridge`, `carplay-cluster-supervisor`, the pairing helper and
the two libraries. Passing on GPL binaries means also passing on their source,
so the release zip leaves them out. `./build_local.sh` adds their
per-firmware folders under `AAClusterMap/carplay/` only when `CARPLAY_SRC`
points at a checkout, for private testing. The source could not be found
online or in the repository history (checked 2026-10-18). omonob sells
paid add-ons. For a public combined release, either ask omonob for the source
or build the CarPlay side from projects whose source is published:
[harman-f/mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay)
(VW group MHI2, GPL-3.0) and
[aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto](https://github.com/aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto)
(Tegra, CarPlay and Android Auto, GPL-3.0, CarPlay core derived from harman-f).

## Car test plan (one session, both phones)

Card: `CARPLAY_SRC=../carplay-maps ./build_local.sh package`, then copy
`dist/sdcard/` to the card.

0. **Hardware decoder first, Android only.** Run the update, reboot, and
   check the cluster map with a route for a few minutes. *Save logs to SD*.
   The player log should show `hwdecode: NvSS decoder ready`. With
   `GAL_PLAYER_STATS=1` it also prints `HW DEC` lines with the frame rate and
   processor load. If the
   cluster stays black, set `GAL_PLAYER_NVSS_OUTPUT=0`, run the update again
   and retry. If neither works, set `GAL_PLAYER_DECODER=sw`.
1. Run the software update from the card. This reinstalls the Android Auto map
   and copies the new menu screen with the CarPlay entries. Reboot.
2. Green menu → AAClusterMap → *Status*. Check that the Android Auto map is
   installed and NavActiveIgnore is loaded.
3. *CarPlay map: install* for your cockpit size. Reboot.
4. *Status* again. Check that NavActiveIgnore and CarPlayClusterControls are
   both listed, and that `dio_manager` is wrapped.
5. **iPhone:** plug in and check stock CarPlay on the centre screen. Then the
   cluster in map view, a route in Apple or Google Maps for two minutes, then
   unplug. Note what the cluster shows at each step.
6. **Android:** the same, with a route in Google Maps. Check that the cluster
   map still works with CarPlay installed.
7. Swap phones once more each way without rebooting.
8. *Save logs to SD* before switching off. This now also saves CarPlay's logs
   (`run_logs/carplay/`), the Java patch lines and the display table.

Keep the engine running or a charger on: the battery has gone flat during
earlier tests.

To back out: *CarPlay map: uninstall* removes only CarPlay. The Android Auto
uninstall (menu or `UNINSTALL` file) removes only the Android Auto map.
