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

The direct link is the better design. The phone's video goes to the cluster
without being decoded and encoded again, so it uses far less processor time
and adds less delay, and it can run faster (CarPlay Maps VC declares 40 fps).
The Android Auto map's player uses 60–120 % of a core at 30 fps.

The display-manager route has two advantages. The unit's own pipeline handles
handing the cluster back to the stock map, and the same output works with
every cluster model, with no per-cluster settings.

Moving CarPlay onto the display manager would make it slower for no gain.
The interesting direction is the reverse: sending the Android Auto video
straight over MOST as well. The bridge's source is not published, so that
would mean writing our own. It's worth trying once the two maps coexist.

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
points at a checkout, for private testing. Before a public combined release:
ask omonob for the source, or get the files from their release instead.

## Car test plan (one session, both phones)

Card: `CARPLAY_SRC=../carplay-maps ./build_local.sh package`, then copy
`dist/sdcard/` to the card.

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
