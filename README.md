# MIB Cluster Map

Puts your phone's map on the digital cluster of Volkswagen-group cars with a
Harman MIB2 / MIB2.5 High head unit ("Discover Pro").

| Phone | On the cluster | State |
|---|---|---|
| Android Auto | The Google Maps or Waze map, live | **Working** on VW `MHI2_ER_VWG13_P4521` and `K4525`, SEAT `MHI2_ER_SEG11_P4708` and `P4709`; Skoda `MHI2_ER_SKG13_P4526` and Golf R `P4512` with a trial line |
| Android Auto, on firmware without a map profile | Turn-by-turn arrows, distance and track ([adi961's jar](https://github.com/adi961/mib2-android-auto-vc), [our fork](https://github.com/MacsInSpace/mib2-android-auto-vc)) | Working on four trains, including SEAT `P4708`/`P4709` |
| Apple CarPlay | The Apple Maps or Google Maps map, live | **First car run**: on the dash of a Golf R (`P4512`); fitting it between the dials is under test. See [CarPlay](docs/CarPlay.md) |

It installs from an SD card as a software update. No toolbox, laptop or
command line is needed. The installer checks the unit and installs what fits
it: the map, the arrows, or nothing. If nothing fits, it collects the files
needed to add your unit and changes nothing.

No VNC and no app on the phone. The phone sends its own cluster video stream,
and the head unit passes it to the cluster the same way it sends the built-in
VW map.

![The phone's map on a Golf 7.5 cluster](thirdparty/after.jpg)

> [!CAUTION]
> This modifies system files on the head unit. A mistake can leave the phone
> connection, or the whole centre screen, not starting. Use it only on a car
> you own, keep the SD card, keep the battery charged, and never install or
> test while driving. No warranty of any kind. Read
> [Safety and recovery](docs/Install.md#safety-and-recovery) first.

## Install

1. **Make the SD card.** Format a 2 to 32 GB card as FAT32. Download the zip
   from [Releases](../../releases) and copy everything inside it to the card:

   ```text
   (SD card)
   ├── ClusterMap/
   ├── Custom/
   ├── metainfo2.txt
   └── _Swdlautorun.txt
   ```

   Put it in **SD slot 1**, with the other slot empty.
2. **Run the update.** Engine running or a charger connected. Hold **MENU**
   until the service screen appears, then `Software updates/versions` >
   `Update` > the SD card > **`MIB Cluster Map`**. Let it finish (a
   "Version back documentation" screen at the end is normal: press
   `Cancel`), then hold the power button for ten seconds to reboot. Audi:
   the update menu is **BACK + upper-left** button and needs developer mode
   switched on in the head unit (5F). An autorun file on the card starts the
   update without the menu: tested on a VW, untested on Audi (see the
   [Install guide](docs/Install.md#route-1-software-update)).
3. **Use it.** Plug in the phone, start a map, and switch the cluster to its
   map view with the steering wheel buttons. iPhone: once after installing,
   **Forget This Car** in its CarPlay settings and plug it in again.

The update writes what it did to `ClusterMap/update_result.txt` on the card.
It also adds a **ClusterMap** screen to the green engineering menu (hold MENU >
`Testmode` > `Green Developer Menu`) for status, logs, uninstall and the
turn-arrows switch.

The green menu and SSH routes, every setting, and recovery are in the
[Install guide](docs/Install.md).

**Uninstall:** green menu > `ClusterMap` > **Uninstall and restore original
state**, then reboot. Or, without the menu: on a computer, move
`UNINSTALL.txt` from the folder `to uninstall, move this file up one folder`
up into `ClusterMap`, and run the same update again.

## Which language should I write in?

Yours. Issues and comments in any language are welcome, and several cars now
working were debugged with people writing in their own. Logs and photos need
no translation at all.

## Will it work on my car?

| Head unit | Firmware train starts | Today |
|---|---|---|
| VW Discover Pro 9.2 in (MIB2.5 High) | `MHI2_ER_VWG13_` | **Map** on `P4521` and `K4525` (software 1367), both road-tested. `P4512` (Golf R) and US `P3662`: install with a trial line. Others wanted |
| SEAT with the Harman unit | `MHI2_ER_SEG11_` | **Map** on `P4708` and `P4709` (1010×376 cluster window). **Arrows** on both |
| Skoda with the Harman unit | `MHI2_ER_SKG13_` | **Map** on `P4526`, car-confirmed (#15). Others wanted |
| VW Discover Pro 8 in (MIB2 High) | `MHI2_ER_VWG11_` | Unknown, but no longer ruled out: this generation links `libautoreceiver_qnx.so.1` beside `libaoa-lite`, not the `libautoreceiver.so` the map hooks today (#28, #33). A different receiver generation, so a profile may not map. Files wanted |
| Audi MIB2 High, Harman/Tegra | `MHI2_ER_AU` | Unknown: `K3346` (A4 B9) still to be rechecked for the receiver name above (#14). An RS3 (software 1168) is still to be tried. The update needs developer mode (see Install) |
| Audi MIB2 High, Qualcomm | `MHI2Q_` | Not this project: see [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay) |
| MIB2 Standard (Composition, Discover Media) | `MST2_` | No. A different unit; nothing here applies |

You need a digital cluster (Active Info Display) for the map. The train is on
the green menu **Status** screen; "Software: 1367" under `Setup` > `System
information` is a hint, not proof. You do not have to work it out: the
installer checks the real firmware itself.

Not listed, or "wanted"? Run the update anyway: it installs nothing and
collects what is needed to add your unit. See
[Getting your unit added](docs/Install.md#getting-your-unit-added).

## Status

Experimental. Developed on a VW Golf 7.5 (`P4521`) and tested on a Tiguan (`P4521`),
a Passat and an Arteon (`K4525`), two SEATs (`P4708`, `P4709`), a Skoda (`P4526`)
and a Golf R (`P4512`). The Android Auto map runs at about 30 frames
per second, with and without a route, and comes back by itself after the
phone is unplugged and plugged in again.

| Part | State |
|---|---|
| Android Auto map, installer and uninstaller over SSH | Tested on cars (Golf `P4521`, SEAT `P4708`) |
| Software update and green menu routes | Tested on cars (Golf `P4521`, Golf R `P4512`) |
| Hardware video decoding (`GAL_PLAYER_DECODER=hw`, off by default) | Fails on the car and falls back to software decoding; under investigation |
| CarPlay map | Shown on a car (Golf R, iPhone over USB) after a firewall fix; layout between the dials under test |
| Long drives, reverse camera, waking from sleep | Road-tested on `K4525`; otherwise little testing |
| Autorun install without the service menu (`Swdlautorun.txt`) | Tested on a car (Golf `P4521`); Audi untested |

Showing the arrows and the map together works on SEAT with
`CLUSTERMAP_KEEP_ARROWS=1`, but not on VW, where the map goes blank when a
route starts. Not possible so far: zooming the cluster map from the steering
wheel ([why](docs/Development.md#zoom)), and switching between the phone's map
and the car's map from the steering wheel.

## Documentation

| Page | For |
|---|---|
| [Install guide](docs/Install.md) | Install routes, the menu, settings, logs, safety and recovery, getting your unit added |
| [CarPlay](docs/CarPlay.md) | The CarPlay map: design, status, testing |
| [Development](docs/Development.md) | How it works, what was learned, adding a firmware, building |

## Reporting a problem

Open an issue with your car, firmware train, what you did and what you saw.
Attach the logs from green menu **Save logs to SD**, saved before rebooting.
Read them first: the system log can contain phone names and Bluetooth
addresses.

## Credits

- **chopinwong01**: [mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc),
  the hook and player this project is forked from. Its design notes and
  development story stay there.
- **andrewleech** and **OneB1t**: VcMOSTRenderMqb, the cluster rendering path
  the player derives from.
- **jilleb**, **olli991** and contributors: the MQB Coding MIB2 Toolbox. Its
  `NavActiveIgnore.jar` (contributed by andrewleech) and the signed header of
  its update metadata are bundled unmodified under `thirdparty/` (MIT).
- **adi961**: mib2-android-auto-vc, the turn-arrows jar. Bundled under
  `thirdparty/` (MIT) as the arrows mode, built from
  [our maintained fork](https://github.com/MacsInSpace/mib2-android-auto-vc).
- **harman-f** ([mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay))
  and **aberbic** ([Audi MHI2 AltScreen](https://github.com/aberbic/Audi-MHI2-Virtual-Cockpit-Altscreen-CarPlay-AndroidAuto)):
  the open CarPlay cluster work the CarPlay map builds on. harman-f's hook is
  included from source under GPL-3.0.
- **Mr-MIBonk** ([M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)):
  the `Swdlautorun.txt` trigger for installing without the service menu.
- **lito69**, **tulio150** and **DaniFR3**: car tests and porting files for
  the SEAT and the settings.
- **kamgurgul**, **wasimlhr** and **luka-dev**: the MHI2Q projects whose notes
  led to the connection-loop fix, and the open QNX toolchain.
- **FFmpeg**: H.264 decoding, statically linked, LGPL v2.1 or later.

## License

GPL-3.0, the same as upstream. See [LICENSE](LICENSE). Release packages
contain files built from this source plus the MIT-licensed items above. They
contain no Volkswagen, Harman or Apple program files.

Not affiliated with or endorsed by Volkswagen AG, Harman, Google or Apple.
Android Auto and Google Maps are trademarks of Google LLC; CarPlay and Apple
Maps are trademarks of Apple Inc.
