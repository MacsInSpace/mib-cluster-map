# Android Auto map on the VW digital cluster (MIB2.5 High)

Shows the Google Maps or Waze map from Android Auto on the Volkswagen Active
Info Display, for Harman "Discover Pro" head units.

No VNC, no wifi and no app on the phone. The phone sends Android Auto's own
cluster video stream over the USB cable, and the head unit passes it to the
cluster the same way it sends the built-in VW map.

It installs from an SD card as a software update. No toolbox, laptop or
command line is needed.

> [!CAUTION]
> This modifies system files on the head unit. A mistake can leave Android Auto
> or the whole infotainment screen not starting. Use it only on a car you own,
> keep the SD card, keep the battery charged, and never install or test while
> driving. No warranty of any kind. Read
> [Safety and recovery](wiki/Install-Guide.md#8-safety-and-recovery) first.

## Will it work on my car?

Today it supports **one firmware on one head unit**:

| | |
|---|---|
| Head unit | Harman MIB2.5 High: "Discover Pro" with the 9.2 inch glass screen |
| Firmware | `MHI2_ER_VWG13_P4521`, shown as **Software: 1367** |
| Cluster | Digital cluster (Active Info Display) that can show the navigation map |
| Phone | Android Auto over USB, already working in the car |
| Also needed | Nothing. The [MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) is optional but recommended as a way back in if something goes wrong |

To check: `MENU` > `Setup` > `System information` on the head unit.

**"Software: 1367" is necessary but not proof.** A second firmware,
`MHI2_ER_VWG13_K4525`, shows the same number and is untested. You do not have
to work this out yourself: the installer checks the real firmware and changes
nothing if it is not supported.

| Head unit | Supported |
|---|---|
| MIB2.5 High, Discover Pro 9.2 inch (`MHI2_ER_VWG13_...`) | **P4521 yes.** Other firmware wanted |
| MIB2 High, Discover Pro 8 inch (`MHI2_..._VWG11_...`) | Not yet. Same family, a port may be possible |
| Skoda and SEAT with the Harman unit | Not yet |
| MIB2 Standard: Composition Media, Discover Media | No. Different hardware and software |
| Audi (`MHI2Q_...`) | No. See [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay) |
| MIB1, MIB3 | No. Different platforms |
| Apple CarPlay | No. See [omonob/MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps) |

The aim is every MIB2.5 High firmware. Each one needs an owner willing to
help; see [Other firmware](#other-firmware). Details:
[Supported units](wiki/Supported-Units.md) and the
[Firmware support matrix](wiki/Firmware-Support-Matrix.md).

## Status

Experimental. It works on one car, a VW Golf 7.5: the cluster map ran at about
30 frames per second, with and without a route.

| Part | State |
|---|---|
| The cluster map itself | Tested on a car |
| The installer and uninstaller, run over SSH | Tested on a car |
| Installing as a software update from the SD card | Built and simulated. **Not yet tested on a car** |
| The green menu screen | Built and simulated. **Not yet tested on a car** |
| The green menu screen on a unit that never had the toolbox | Unknown |
| Long drives, phone reconnects, reverse camera, waking from sleep | Little or no testing |

What it does not do:

- **Zoom the cluster map from the steering wheel.** No input was found that
  makes the phone zoom it. [Findings](wiki/Cluster-Zoom-Findings.md).
- **Show turn arrows together with the map.** It is one or the other; see
  [Turn arrows instead](#turn-arrows-instead).

## Install

The [Quick start](wiki/Quick-Start.md) has every step with explanations. In
short:

**1. Make the SD card.** Format a 2 to 32 GB card as FAT32. Download the zip
from [Releases](../../releases) and copy everything inside it to the card:

```text
(SD card)
├── AAClusterMap/
├── Custom/
└── metainfo2.txt
```

Put it in **SD slot 1**, with the other slot empty.

**2. Run the update.** Engine running or a charger connected. Hold the
**MENU** button until the service screen appears, then
`Software updates/versions` > `Update` > the SD card >
**`Android Auto Cluster Map`**. Let it finish, then hold the power button for
ten seconds to reboot.

**3. Use it.** Plug in the phone, open Google Maps in Android Auto, and switch
the cluster to its map view with the steering wheel buttons.

What the update does without asking:

- checks the firmware, and stops without changing anything if it is not supported;
- adds the NavActiveIgnore patch if it is missing, so the map stays up while
  the phone navigates (only on firmware where that patch is known to work);
- switches off the turn-by-turn arrows jar if it is loaded, because the two
  cannot run together;
- installs the cluster map and keeps the original files as backups;
- copies an `AAClusterMap` screen into the unit's green engineering menu and
  switches that menu on.

It writes what it did to `AAClusterMap/update_result.txt` on the card. A good
run ends with `AACLUSTER_INSTALL_OK`.

### The menu screen

Hold MENU > `Testmode` > `Green Developer Menu` > **`AAClusterMap`**:

| Entry | What it does |
|---|---|
| 1. Status and compatibility check | Shows the firmware, whether it is supported, and what is installed |
| 2. Install cluster map | The same install as the update |
| Uninstall and restore original state | Full revert |
| Switch to turn-by-turn arrows instead (no map) | See below |
| Save logs to SD | For reporting a problem. Do it before rebooting |
| Collect files for porting (quick) | For owners of other firmware |
| Collect for porting, with Java image (55 MB, slow) | Only for a turn-arrows port |

If you already use the toolbox and would rather not run an update, the
[Install guide](wiki/Install-Guide.md) covers adding the screen from the
toolbox, and installing over SSH.

## Uninstall

Either:

- green menu > `AAClusterMap` > **Uninstall and restore original state**; or
- on a computer, open `AAClusterMap` on the card and move `UNINSTALL.txt` out
  of the folder named `to uninstall, move this file up one folder`, up into
  `AAClusterMap` itself. Run the same update again. Move the file back
  before installing again.

Then reboot. Both put back the original system file, delete everything that
was installed, and undo the two start-up changes: the turn-arrows jar is
switched back on if the installer switched it off, and NavActiveIgnore is
removed if the installer added it.

The engineering menu stays switched on. That is the one thing uninstalling
does not undo; it is harmless.

## Turn arrows instead

If you would rather have a simple next-turn arrow, distance and track
information on the cluster, the menu can switch to
[adi961's mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc)
instead: green menu > `AAClusterMap` > **Switch to turn-by-turn arrows
instead**. It removes the map first. Running the install again switches back.

Its author lists `MHI2_ER_VWG13_P4521` and `MHI2_ER_VWG13_K4525` as tested,
and the menu entry refuses other firmware.

## Other firmware

Everything specific to one firmware is a single table entry in the code, so
adding a firmware is mostly a matter of someone with that unit helping.

**If your unit is not supported:** make the SD card and run the update anyway.
It installs nothing. Instead it copies the handful of files a port needs,
about 2.5 MB, into a `porting_...` folder on the card. Then open an issue with
your car, your firmware, and the `info.txt` from that folder.

**Do not post the other files in that folder.** They are Volkswagen and Harman
software and are not ours to distribute.

What happens next, and how to do the port yourself:
[Porting to another firmware](wiki/Porting-To-Another-Firmware.md).

## How it works

1. A small library is loaded into the head unit's own Android Auto program. It
   tells the phone there is a second display, and receives the video the phone
   sends for it.
2. A player decodes that video and draws it into a window on the head unit.
3. The head unit sends that window to the cluster over the car's MOST bus,
   the path the built-in map uses.

The library depends on the exact layout of that Android Auto program, which is
why each firmware needs its own profile. On a firmware it does not recognise
it does nothing at all.

## What this fork adds

This is a fork of
[chopinwong01/mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc),
which did the hard part: the hook and the player. This fork adds:

- **A build anyone can run.** Upstream needs a private toolchain image.
  `build_local.sh` uses the open
  [luka-dev/qnx65-armv7-toolchain](https://github.com/luka-dev/qnx65-armv7-toolchain).
- **A fix for a connection loop.** With a cluster display the phone sends
  navigation messages the 2018 receiver does not know, and the receiver's reply
  makes the phone drop the link.
  [Details](wiki/Navigation-Status-Messages.md).
- **A fix for the cluster going blank when a route starts**, caused by the
  turn-arrows jar being active at the same time.
- **One-step install and uninstall** as a software update, with the firmware
  check, NavActiveIgnore and the conflicting jar handled automatically.
- **A green menu screen** for status, install, uninstall, logs and file
  collection.
- **Guarded edits.** Each change to a system file is written to a new file,
  checked, and only then swapped in. Originals are kept.
- **Firmware profiles**, a tool that proposes a profile from a unit's files,
  and a way to trial one without rebuilding.
- **Pieces missing from upstream's published tree**: a helper library's build
  step and a status helper.
- **Quiet logging by default**, kept in memory only.
- **An investigation of cluster map zoom.**

## Documentation

| Page | For |
|---|---|
| [Quick start](wiki/Quick-Start.md) | Installing, step by step |
| [Supported units](wiki/Supported-Units.md) | Whether your car is covered, and common questions |
| [Firmware support matrix](wiki/Firmware-Support-Matrix.md) | Which firmware is supported, derived or wanted |
| [Install guide](wiki/Install-Guide.md) | Reference: all install routes, settings, safety and recovery, building |
| [Porting to another firmware](wiki/Porting-To-Another-Firmware.md) | Adding a firmware |
| [Navigation status messages](wiki/Navigation-Status-Messages.md) | The connection loop and its fix |
| [Cluster map zoom](wiki/Cluster-Zoom-Findings.md) | What was tried and why it is not implemented |
| [Receiver layout verification](wiki/Receiver-Layout-Verification.md) | The layouts a port has to re-check |
| [Upstream README](wiki/Upstream-README.md) and [wiki](wiki/Home.md) | Architecture and development history |

## Building

Needs Docker. Build the toolchain image once, then:

```sh
./build_local.sh        # hook, helper library, FFmpeg, player, SD card package, zip
```

Details are under "Building" in the [Install guide](wiki/Install-Guide.md).

## Reporting a problem

Open an issue with your car, your firmware, what you did and what you saw.
Attach the logs from **Save logs to SD** if you can, collected before
rebooting. Read them first: the system log can contain phone names and
Bluetooth addresses.

## Credits

- **chopinwong01**: the original project this is forked from.
- **andrewleech** and **OneB1t**: VcMOSTRenderMqb, the cluster rendering path
  the player derives from.
- **jilleb**, **olli991** and contributors: the MQB Coding MIB2 Toolbox. Its
  `NavActiveIgnore.jar` (contributed by andrewleech) and the signed header of
  its update metadata are bundled unmodified under `thirdparty/` (MIT).
- **adi961**: mib2-android-auto-vc. Its 0.1.4 jar is bundled unmodified under
  `thirdparty/` (MIT) as the optional arrows mode.
- **kamgurgul**, **wasimlhr** and **luka-dev**: the MHI2Q projects whose notes
  on the "unexpected message" reply and the newer navigation messages pointed
  to the loop fix, and the open QNX toolchain.
- **FFmpeg**: H.264 decoding, statically linked, LGPL v2.1 or later.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE). The release packages
contain files built from this source, plus the three MIT-licensed items
credited above. They contain no Volkswagen or Harman program files.

Not affiliated with or endorsed by Volkswagen AG, Harman or Google. Android
Auto and Google Maps are trademarks of Google LLC.
