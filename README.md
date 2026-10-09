# Android Auto map on the VW digital cluster (MIB2.5 High)

Shows the Google Maps (or Waze) map from Android Auto on the Volkswagen Active
Info Display, for Harman MIB2.5 "Discover Pro" head units.

No VNC, no wifi and no app on the phone. The phone sends Android Auto's own
cluster video stream over the USB cable, and the head unit passes it to the
cluster the same way it sends the stock VW map.

This is a fork of
[chopinwong01/mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc),
which did the hard part. This fork adds an open build, fixes found on a car,
an installer that needs no SSH, and prebuilt packages.

> [!CAUTION]
> This modifies system files on the head unit. A mistake can leave Android Auto
> or the whole infotainment screen not starting. Use it only on a car you own,
> keep the SD card with its backups, keep the battery charged, and never
> install or test while driving. No warranty of any kind.

## Supported

| | |
|---|---|
| Head unit | Harman MIB2.5 High, "Discover Pro" 9.2 inch |
| Firmware | `MHI2_ER_VWG13_P4521`, software **1367**, and nothing else |
| Cluster | Active Info Display that can show the navigation map |
| Phone | Android Auto over USB |
| Needs | [MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) installed, with its NavActiveIgnore patch |

**Check the firmware train, not just "Software: 1367".** Two trains carry that
number and only P4521 is tested. Full details, other MIB generations and other
brands: [Which cars and head units are supported](wiki/Supported-Units.md).

The hook contains addresses inside the stock Android Auto program for this
exact firmware. On any other firmware it detects the mismatch, logs it and
leaves Android Auto untouched.

## Status

Working on one car: a VW Golf 7.5. The cluster map ran at about 30 frames per
second with and without a route. Long drives, reconnects, the reverse camera
and waking from sleep have had little testing. Treat it as experimental.

| Works | Does not work |
|---|---|
| Phone map on the cluster, with or without a route | Zooming the cluster map from the steering wheel |
| Main screen Android Auto unchanged | Turn arrows beside the map (the turn-by-turn jar must be off) |
| Install, status, logs and full uninstall from the green menu (untested on a car; the SSH route is tested) | Any other firmware |
| Optional switch to turn-by-turn arrows instead of the map | Map and arrows at the same time |

## Install

1. Download the zip from [Releases](../../releases) and extract it to the root
   of a FAT32 SD card.
2. Put the card in slot 1 and follow the
   [Install guide](wiki/Install-Guide.md): from the green menu, or over SSH.
3. Reboot the unit, plug in the phone, and put the cluster in map view.

**Uninstall and restore original state** is one menu entry or one command. It
puts back the original files, including anything the installer switched off.
If you would rather have simple turn arrows than the map, the same menu can
switch to those instead. See [Safety and recovery](wiki/Install-Guide.md#8-safety-and-recovery)
before you start.

## What this fork changes

- **Open toolchain.** Upstream needs a private Docker image. `build_local.sh`
  builds everything with
  [luka-dev/qnx65-armv7-toolchain](https://github.com/luka-dev/qnx65-armv7-toolchain).
- **Connection loop fixed.** With a cluster display the phone sends navigation
  messages the 2018 receiver does not know, and the receiver's reply makes the
  phone reset the link. The hook drops that reply.
  [Details](wiki/Navigation-Status-Messages.md).
- **Blank cluster on route start fixed.** Caused by `VCAndroidAuto.jar`; the
  installer checks for it and removes its start-up line, reversibly.
- **Installer fixes.** Counts the supervisor's environment limit correctly,
  keeps the settings on the unit so the SD card can be removed, removes what it
  installed, and checks for the NavActiveIgnore patch.
- **Missing pieces restored.** The helper library build step and a status
  helper that upstream's published tree lacks.
- **Green menu screen.** Install, status, logs and uninstall without SSH.
- **Quiet by default.** Debug logging is off; a small log is kept in RAM.
- **Zoom investigated.** No input makes the phone zoom its cluster map.
  [Findings](wiki/Cluster-Zoom-Findings.md).

## Documentation

- [Which cars and head units are supported](wiki/Supported-Units.md)
- [Install guide](wiki/Install-Guide.md)
- [Navigation status messages and the connection loop](wiki/Navigation-Status-Messages.md)
- [Cluster map zoom: what was tried](wiki/Cluster-Zoom-Findings.md)
- [Receiver layout verification](wiki/Receiver-Layout-Verification.md), for anyone porting to another firmware
- [Upstream README](wiki/Upstream-README.md) and the rest of the upstream [wiki](wiki/Home.md): architecture and development history

## Building

Needs Docker. See "Building" in the [Install guide](wiki/Install-Guide.md).

```sh
./build_local.sh        # hook, helper library, FFmpeg, player, SD card package, zip
```

## Credits

- **chopinwong01**: the original project this is forked from.
- **andrewleech** and **OneB1t**: VcMOSTRenderMqb, the cluster rendering path the player derives from.
- **jilleb**, **olli991** and contributors: the MQB Coding MIB2 Toolbox.
- **adi961**: mib2-android-auto-vc. Its 0.1.4 jar is bundled unmodified under `thirdparty/` (MIT) as the optional arrows mode.
- **kamgurgul**, **wasimlhr** and **luka-dev**: the MHI2Q projects whose notes on the "unexpected message" reply and the newer navigation messages pointed to the loop fix, and the open QNX toolchain.
- **FFmpeg**: H.264 decoding, statically linked, LGPL v2.1 or later.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE). The release packages
contain files built from this source plus the MIT-licensed `VCAndroidAuto.jar`. They contain no Volkswagen or
Harman firmware.

Not affiliated with or endorsed by Volkswagen AG, Harman or Google. Android
Auto and Google Maps are trademarks of Google LLC.
