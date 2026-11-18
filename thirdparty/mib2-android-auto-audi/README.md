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

| Jar | What it does | Audi classes it patches |
|---|---|---|
| `coverart_hook.jar` | CarPlay cover art + track data into the media/BAP layer | `de/audi/app/combi/bap/app/audio/AppConnectorTerminalMode`, `TerminalModeBapCombi$EventListener` |
| `rgd_hook.jar` | CarPlay route-guidance display (turn arrow, distance, road name) | `de/audi/tghu/navi/app/cluster/ClusterService`, `RgdCombiBAPListener`, `DisplayManagerMIB2High` |
| `dpad_hook.jar` | Steering-wheel D-pad / cursor controller for CarPlay | `de/audi/app/terminalmode/dsi/carplay/CarplayDSILifecycleController` |
| `pdc_hook.jar` | Parking-sensor popup beside CarPlay | `ExternalEventsListener`, `HighPriorityResourceTracker`, `ParkingSystemControllerComponentEvo` |
| `AAcoverart_hook.jar` | Android Auto cover art + track info (DSIAndroidAuto2 listener) | Same classes as `coverart_hook.jar` (mutually exclusive) |
| `AArgd_hook.jar` | Android Auto turn arrows + distance + road name (DSIAndroidAuto2 listener) | Same classes as `rgd_hook.jar` (mutually exclusive) |

`coverart_hook.jar` / `rgd_hook.jar` are for CarPlay; `AAcoverart_hook.jar` /
`AArgd_hook.jar` are for Android Auto. The CarPlay and Android Auto jars patch
the same Audi stock classes, so they are mutually exclusive — load only one
pair.

## Build

Android Auto jars are built from `java/androidadio/` with `build.sh` — compiles
Java source with `javac --release 8` against `TRANSFER/lsd.jar`, then strips
class files to version 46 (no StackMapTable) for the Audi J9 VM. Output goes to
`build/AAAndroidAutoTrack.jar` and `build/AAAndroidAutoTurns.jar`; they are then
renamed to `AAcoverart_hook.jar` and `AArgd_hook.jar` respectively.

## Important: CarPlay origin

These jars come from a CarPlay project (`mhi2-au37x-carplay`). They work on the
same hardware platform (AU37x / P5089) as your Audi A3 8V, but:

- `coverart_hook.jar` reads cover art from a file path (`com/mhi2/carplay/coverart/CoverArt`, `COVERART_PATH`) — on CarPlay that file is written by the CarPlay system; for Android Auto the same cover-art slot must be fed from the Android Auto now-playing data.
- `rgd_hook.jar` shows route guidance on the cluster; on Android Auto the maneuver data must arrive through the same BAP channels the jar reads.

They are included as the starting point for an Audi Android Auto port. If they do not show Android Auto track names/cover art on your car, the classes in `coverart_hook.jar` (`AppConnectorTerminalMode$CoverArtProvider`, `CoverArtProviderMux`) are where the Android Auto data would need to be hooked in.

## Integration

1. `build_local.sh` copies the jars to the SD card's `thirdparty/` folder:
   - CarPlay: `coverart_hook.jar`, `rgd_hook.jar`, `dpad_hook.jar`, `pdc_hook.jar`
   - Android Auto: `AAcoverart_hook.jar`, `AArgd_hook.jar`
2. `config/profiles.conf`: give the `MHI2_ER_AU37x_P5089` train the `info` flag once you have confirmed the cover-art/turn-info classes work on your train:
   ```
   train MHI2_ER_AU37x_P5089 map info
   ```
3. `config/gal_dualscreen.conf`: set one of:
   - CarPlay: `CLUSTERMAP_AUDI_COVER=1` / `CLUSTERMAP_AUDI_TURNS=1`
   - Android Auto: `CLUSTERMAP_AA_COVER=1` / `CLUSTERMAP_AA_TURNS=1`
   Never set both a CarPlay and an Android Auto option at once — they patch the same classes.
4. `scripts/enable_hook.sh`: handles both CarPlay and Android Auto jar install/removal, keyed on `CLUSTERMAP_AUDI_COVER` / `CLUSTERMAP_AUDI_TURNS` / `CLUSTERMAP_AA_COVER` / `CLUSTERMAP_AA_TURNS`.
5. `build_local.sh`: adds the Audi jars to the `thirdparty/` copy so they ship on the SD card.

## Testing

- Install with the cover-art hook first (`CLUSTERMAP_AUDI_COVER=1` for CarPlay or `CLUSTERMAP_AA_COVER=1` for Android Auto), then try `CLUSTERMAP_AUDI_TURNS=1` / `CLUSTERMAP_AA_TURNS=1` for turn arrows.
- Logs: check `/tmp/VCAndroidAuto.log` and the green menu "Save logs to SD". Put a file named `MIBLogger` containing `DEBUG` on the SD card root for fuller logging.

## Compatibility

The chefranov install.sh refuses firmware older than P5089 on AU37x ER builds ("P5089 is the tested build"). Your train is P5089 — the tested one. Do not install these jars on a different AU37x build without checking chefranov's compatibility notes first.

Android Auto jars are class version 46 (J9 VM compatible) — no StackMapTable, no StringBuilder, no invokedynamic.