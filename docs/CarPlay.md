# CarPlay map

**State: in development. Not in any release yet.**

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
  is byte-identical on VW MU1367 (`P4521`, `K4525`) and, by harman-f's
  survey, SEAT MU1447. The installer will check that hash and install CarPlay
  only on that exact file.
- **Rendering:** `stream-player` reads that socket instead of Android Auto's
  and uses the same hardware decoder and cluster switching.
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

## Steps

| Step | State |
|---|---|
| Hardware decoder in `stream-player` (`GAL_PLAYER_DECODER=hw`, off by default) | Built; first car test under way (with Android Auto) |
| harman-f's hook builds with this project's toolchain | Done, no warnings |
| Bundle the hook from source, with its notice | To do |
| `stream-player` input from the CarPlay socket | To do |
| Installer: `dio_manager` entry, hash check, uninstall | To do |
| Car test with an iPhone | To do |

## Testing

When a test card exists: run the update, reboot, then with the iPhone check
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
