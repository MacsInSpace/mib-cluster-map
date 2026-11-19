# VCAndroidAuto.jar (Audi build)

Audi counterpart of `thirdparty/mib2-android-auto-vc/` (MacsInSpace's maintained fork of adi961's `mib2-android-auto-vc`, MIT licensed).

This folder contains jars ported from
[chefranov/mhi2-au37x-carplay](https://github.com/chefranov/mhi2-au37x-carplay)
(`bin/`), which were built and car-tested on the same MIB2 AU37x platform as
your Audi A3 8V (`MHI2_ER_AU37x_P5089`). They patch Audi stock HMI classes
(instead of the VW `de/vw/mib/*` classes that `VCAndroidAuto.jar` replaces).

It also contains Android Auto jars built from source in `java/androidadio/`:
- `AAcoverart_hook.jar` — Android Auto now-playing cover art / track info
- `AArgd_hook.jar` — Android Auto turn arrows, distance, road name

## Jars in this folder

| Jar | What it does | How it works |
|---|---|---|
| `coverart_hook.jar` | CarPlay cover art + track data into the media/BAP layer | Patches `AppConnectorTerminalMode` class (CarPlay file-path data) |
| `rgd_hook.jar` | CarPlay route-guidance display (turn arrow, distance, road name) | Patches `ClusterService` class (CarPlay RGI data) |
| `dpad_hook.jar` | Steering-wheel D-pad / cursor controller for CarPlay | Patches `CarplayDSILifecycleController` class |
| `pdc_hook.jar` | Parking-sensor popup beside CarPlay | Patches `ExternalEventsListener`, `ParkingSystemControllerComponentEvo` |
| `AAcoverart_hook.jar` | Android Auto cover art + track info | OSGi service lookup: `AppConnectorMedia.updateCurrentStation()` + `IPictureManager.responseCoverArt()` (DSIAndroidAuto2 data) |
| `AArgd_hook.jar` | Android Auto turn arrows + distance + road name | OSGi service lookup: `ClusterService.updateManeuverDescriptor()` / `updateDistanceToNextManeuver()` (DSIAndroidAuto2 data) |

`coverart_hook.jar` / `rgd_hook.jar` are for CarPlay; `AAcoverart_hook.jar` /
`AArgd_hook.jar` are for Android Auto. CarPlay jars patch Audi stock classes;
AA jars use OSGi service lookup to call existing services directly. Because
they work at different levels, CarPlay and Android Auto can be enabled
simultaneously — set `CLUSTERMAP_AUDI_*` and `CLUSTERMAP_AA_*` options
independently in `config/gal_dualscreen.conf`.

Within each pair, the turns jar already carries cover art, so cover is
redundant when turns is enabled.

## Build

Android Auto jars are built from `java/androidadio/` with `build.sh` — compiles
Java source with `javac --release 8` against `TRANSFER/lsd.jar`, then strips
class files to version 46 (no StackMapTable) for the Audi J9 VM. Output goes to
`build/AAAndroidAutoTrack.jar` and `build/AAAndroidAutoTurns.jar`; they are then
renamed to `AAcoverart_hook.jar` and `AArgd_hook.jar` respectively.

## Important: CarPlay origin

The CarPlay jars come from [chefranov/mhi2-au37x-carplay](https://github.com/chefranov/mhi2-au37x-carplay).
They work on the same hardware platform (AU37x / P5089) as your Audi A3 8V:

- `coverart_hook.jar` reads cover art from a file path
  (`com/mhi2/carplay/coverart/CoverArt`, `COVERART_PATH`) — on CarPlay that
  file is written by the CarPlay system.
- `rgd_hook.jar` shows route guidance on the cluster from CarPlay's RGI system.

The Android Auto jars are source-reconstructed: they do not patch classes.
Instead they implement `DSIAndroidAuto2Listener` and use OSGi to look up
existing Audi services (`AppConnectorMedia`, `IPictureManager`, `ClusterService`)
and call their methods directly with DSIAndroidAuto2 now-playing / navigation
data.

## Integration

1. `build_local.sh` copies all jars to the SD card's `thirdparty/` folder as
   part of the main ClusterMap package — no separate install needed:
   - CarPlay: `coverart_hook.jar`, `rgd_hook.jar`, `dpad_hook.jar`, `pdc_hook.jar`
   - Android Auto: `AAcoverart_hook.jar`, `AArgd_hook.jar`
2. `config/profiles.conf`: give the `MHI2_ER_AU37x_P5089` train the `info` flag:
   ```
   train MHI2_ER_AU37x_P5089 map info
   ```
3. `config/gal_dualscreen.conf`: set any combination of:
   - CarPlay: `CLUSTERMAP_AUDI_COVER=1` / `CLUSTERMAP_AUDI_TURNS=1`
   - Android Auto: `CLUSTERMAP_AA_COVER=1` / `CLUSTERMAP_AA_TURNS=1`
   CarPlay and Android Auto can both be enabled at the same time.
4. `scripts/enable_hook.sh`: installs/removes jars based on the four config
   options. `scripts/disable_hook.sh`: removes all jars on uninstall.
5. `build_local.sh`: adds the Audi jars to the `thirdparty/` copy so they ship
   on the SD card.

## Testing

- Install with cover-art hooks first (`CLUSTERMAP_AUDI_COVER=1` for CarPlay
  or `CLUSTERMAP_AA_COVER=1` for Android Auto), then try turn arrows
  (`CLUSTERMAP_AUDI_TURNS=1` / `CLUSTERMAP_AA_TURNS=1`).
- Logs: check `/tmp/VCAndroidAuto.log` and the green menu "Save logs to SD".
  Put a file named `MIBLogger` containing `DEBUG` on the SD card root for
  fuller logging. Our AA jars log "media connector found", "picture manager
  found", "DSIAndroidAuto2 service obtained", "track updated", "cover art
  updated", "maneuver update", "distance update".

## Compatibility

The chefranov install.sh refuses firmware older than P5089 on AU37x ER builds
("P5089 is the tested build"). Your train is P5089 — the tested one. Do not
install these jars on a different AU37x build without checking chefranov's
compatibility notes first.

Android Auto jars are class version 46 (J9 VM compatible) — no StackMapTable,
no StringBuilder, no invokedynamic.