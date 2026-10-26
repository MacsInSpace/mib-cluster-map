# CarPlay map

**State: built, not yet tested on a car. Not in any release yet.**

The goal is one package that puts the phone's map on the cluster for both
phone types. Only one phone projects at a time, so the two only have to share
the cluster, never use it at once.

## Design

Android Auto already reaches the cluster like this:

```text
phone video → hook in the Android Auto program → stream-player
            → display-manager window → the unit's own encoder → MOST → cluster
```

CarPlay will use the same second half. Only the capture differs:

```text
iPhone video → hook in the CarPlay program (dio_manager) → stream-player → … same path
```

- **Capture:** [harman-f/mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay)'s
  open-source hook (GPL-3.0). It asks the iPhone for CarPlay's cluster
  display (stream type 111), receives its video, and hands plain H.264 to a
  local socket (`127.0.0.1:19820`). It loads into `dio_manager` through
  `LD_PRELOAD` in `smartphone_integrator.json`, the file the Android Auto hook
  already uses, so no program file is patched.
- **It fits these units exactly.** The CarPlay library it was written and
  car-tested against (`libairplay.so`, SHA-256 `193a4fd9…46b5`, Skoda MU1440)
  is byte-identical on VW MU1367 (`P4521`, `K4525`), on the Golf R's `P4512`
  (where the installer accepted it and the map reached the dash) and, by
  harman-f's survey, SEAT MU1447. The installer installs CarPlay only when the unit's
  `libairplay.so` is that build (703688 bytes); on any other it installs the
  Android Auto map alone. The hook also checks the functions it attaches to
  and switches itself off if they differ.
- **Getting your build looked at.** **Collect files for porting** copies
  `libairplay.so` onto the card beside the Android Auto files, under whatever
  name the unit carries, so a CarPlay port can be checked without a second
  round trip. Email the `porting_*` folder; it holds Volkswagen/Harman
  binaries and should not be posted publicly.
- **Trying it on another build.** `CLUSTERMAP_CARPLAY_TRIAL=<size>` in
  `gal_dualscreen.conf` lets the installer accept a stated `libairplay.so`
  size; the message it prints when it refuses gives the number to use. This
  is weaker than it sounds, in the safe direction: the hook attaches by
  exported symbol name (`AirPlayReceiverSessionStart` and nine others), not
  by address, and compares the first eight bytes of every function it
  trampolines, so it refuses a build that does not fit on its own. After a
  trial install, read `carplay/altscreen111.log` from **Save logs to SD**:
  `missing symbol <name>` means that build does not export what the hook
  needs, `prologue mismatch` means the function is not the shape it patches,
  and neither leaves CarPlay altered. Asked for in #10 (US `P3662`).
- **Source, not binary:** the hook is built here from harman-f's published
  development source (`thirdparty/mhi2_altscreen_carplay/`, provenance in its
  `PROVENANCE.md`), not from their car-tested binary, for which no exact
  source is published.
- **Rendering:** `stream-player` reads that socket instead of Android Auto's
  and uses the same decoder and cluster switching. CarPlay, unlike Android
  Auto, can be asked for any size, so it is asked for the cluster map
  window's size (see [Install](Install.md#cluster-map-window)).
- **Reference renderer:** [aberbic's Audi MHI2 project](https://github.com/aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto)
  does both phones this way on an Audi Tegra unit, with a CarPlay core derived
  from harman-f's.

### Why through the display manager, not straight onto MOST

The cluster only ever receives video from the head unit's own hardware
encoder. Drawing the phone's map into a display-manager window keeps it that
way: the cluster gets the stream it was built for, and handing back to the
stock map is the unit's own job.

The alternative, used by omonob's CarPlay Maps VC and harman-f's default
path, repackages the phone's H.264 and writes it straight to the MOST channel
(`/dev/mlb/isoTX2`). That saves decoding on the unit, but owners report lag
and coloured blocks on a Golf 7.5 MU1367 with the 12.3-inch cockpit (omonob
issue #10), and harman-f only proved it on the 10-inch Skoda cockpit.

It should also make the cockpit size irrelevant: the unit's encoder scales
the window for whichever cluster is fitted, as it already does for the
Android Auto map at 800×480. That still has to be shown on a car.

## How it runs

The installer builds one library, `libcarplay_cluster.so`: harman-f's hook
plus a small launcher. It adds three entries to the `carplay` program's
environment in `smartphone_integrator.json`, in the same edit as the Android
Auto entry:

```text
LD_PRELOAD=/mnt/app/eso/lib/gal_dualscreen/libcarplay_cluster.so
ALTSCREEN111_WIDTH=<cluster map width>
ALTSCREEN111_HEIGHT=<cluster map height>
```

The iPhone sends the cluster video to TCP port 6031, which the unit's
firewall blocks: it allows only the stock CarPlay ports on `carplay0`, the
iPhone's USB link. The installer adds one rule after the stock CarPlay line
in each `/mnt/system/etc/pf*.conf`, read at the next boot:

```text
pass in quick on carplay0 proto tcp from any to any port 6031 allow-opts # clustermap carplay map
```

It opens nothing on Wi-Fi, mobile data or the debug port. The first install
keeps each file as `pf*.conf.clustermap.original`; the uninstall removes
only the marked line, so rules other tools added (such as the MIB2
Toolbox's SSH rule) stay.

The iPhone keeps the car and its instruction card inside a safe area. The
installer writes it to `/mnt/app/root/mibr-carplay111-safearea.conf` from
`GAL_SECONDARY_INSETS`, the same setting that keeps the Android Auto map
clear of the dials, scaled to the window (800x480 with the default insets:
546x400 at 127,40).

An iPhone that knew the car before the install keeps its old idea of the car
and never asks for the cluster stream (Golf R). Once after installing: on the
iPhone, `Settings` > `General` > `CarPlay` > the car > **Forget This Car**,
then plug it in again.

When an iPhone connects, the unit starts `dio_manager`, the library loads,
and the launcher starts `carplay_cluster.sh`. That script watches the hook's
state file (`/tmp/mibr-carplay111.state`): while it says `streaming` it runs
`stream-player` on `tcp://127.0.0.1:19820`; when it stops, or `dio_manager`
ends, it stops the player, which hands the cluster back to the stock map.

Install over SSH with `enable_hook.sh --no-carplay` to leave CarPlay alone.
The status check says whether the CarPlay map is installed and what the
stream is doing. **Save logs to SD** copies its logs to
the `carplay/` folder of each `ClusterMap/run_logs/` save.

The installer skips CarPlay, and still installs the Android Auto map, when:

- the unit's `libairplay.so` is a different build;
- CarPlay Maps VC is installed (see below);
- the `carplay` entry already preloads a library, or would pass 10
  environment entries.

## Steps

| Step | State |
|---|---|
| Hardware decoder in `stream-player` (`GAL_PLAYER_DECODER=hw`, off by default) | Built; first car test under way (with Android Auto) |
| harman-f's hook built from source, with its notice | Done, no warnings |
| `stream-player` input from the CarPlay socket | Done (`--no-ack`) |
| Installer: `dio_manager` entry, library check, uninstall | Done; simulated against this unit's configuration |
| Car test with an iPhone | Golf R (P4512): hook loads, the phone sets up the cluster stream after "Forget This Car", its video was blocked by the unit firewall until the rule above; with it, the map shows on the dash. Safe area added after the card and car sat under the dials |

## Testing

Run the update, reboot, then with the iPhone check
stock CarPlay on the centre screen, the cluster in map view, a route for two
minutes, and unplugging. Then the same with the Android phone, and swap
phones twice without rebooting. **Save logs to SD** before switching off.
An iPad cannot be used: CarPlay is iPhone only.

## If you already use CarPlay Maps VC

omonob's [CarPlay Maps VC](https://github.com/omonob/MHI2-Carplay-Maps)
installs separately with its own installer. This package does not install it,
but stays out of its way:

- Its navigation patch, `CarPlayNavigationPatch.jar`, is the same nine classes
  as NavActiveIgnore. The installer counts it as NavActiveIgnore, and the
  uninstall leaves NavActiveIgnore in place while CarPlay Maps VC uses it.
- It joins its jars onto an existing Java patch line. Jars are added and
  removed here as single entries of a line, so removing ours never takes its
  jar with it.

Its native programs have no published source, which is why this package
builds its CarPlay side from harman-f's instead.
