# MIB Cluster Map

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/macsinspace)
If this saves you a dealer visit, a [coffee](https://buymeacoffee.com/macsinspace) helps pay for the AI tokens that build it.

Puts your phone's map on the digital cluster of Volkswagen-group cars with a
Harman MIB2 / MIB2.5 High head unit ("Discover Pro").

| Phone | On the cluster | State |
|---|---|---|
| Android Auto | The Google Maps or Waze map, live | **Working** on VW `MHI2_ER_VWG13_P4521`, `K4525`, `P4512` and `P4174` (Golf R, Passat B8, Passat R wagon, Golf Alltrack), VW `MHI2_ER_VWG11_K3342` (Discover Pro 8 in, Passat B8 and Passat GTE), SEAT `MHI2_ER_SEG11_P4708` and `P4709`, Skoda `MHI2_ER_SKG13_P4526` and `P4523`, Audi A4 B9 and Q5 FY `MHI2_ER_AUG22_K3346`, Audi A3/S3 8V `MHI2_ER_AU37x_P5089`, `P5153` and `P4203`, Audi A6 and A7 C7.5 `MHI2_ER_AU57x_K3663`, US Audi A7 C7.5 `MHI2_US_AU57x_K3341`, VW `MHI2_ER_VWG11_P3301`, US `MHI2_US_VWG13_P3662` |
| Android Auto, on firmware without a map profile | Turn-by-turn arrows, distance and track ([adi961's jar](https://github.com/adi961/mib2-android-auto-vc), [our fork](https://github.com/MacsInSpace/mib2-android-auto-vc)) | Working on four trains, including SEAT `P4708`/`P4709` |
| Apple CarPlay | The Apple Maps or Google Maps map, live | **Working** on a Golf R and a Passat B8 (`P4512`, #67), a SEAT (`P4709`), a Golf (`K4525`), a Tiguan (`P4521`) an Audi A7 C7.5 (`K3663`, three cars, #68) a Golf GTE (`P3657`, #100), a Golf 7 (`K3332`, #45) and two VW Discover Pro 8 in (`K3342` MU1427, #62 and #111; no trial line needed since v1.2.6), with the iPhone on a cable. Many wireless adapters never send the cockpit picture ([CarPlay](docs/CarPlay.md#wireless-adapters)). It can switch back to the car's own map while driving, under investigation (#19, #43). See [CarPlay](docs/CarPlay.md) |

It installs from an SD card as a software update. No toolbox, laptop or
command line is needed. The installer checks the unit and installs what fits
it: the map, the arrows, or nothing. If nothing fits, it collects the files
needed to add your unit and installs nothing.

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
   └── Swdlautorun.txt
   ```

   Put it in **SD slot 1**, with the other slot empty.
2. **Run the update.** Engine running or a charger connected. On most units
   the card starts the update by itself within a couple of minutes
   (`Swdlautorun.txt`; the installer switches it off again when it
   finishes). If it does not, hold **MENU** until the service screen
   appears, then `Software updates/versions` > `Update` > the SD card >
   **`MIB Cluster Map`**. Let it finish (a "Version back documentation"
   screen at the end is normal: press `Cancel`), then hold the power button
   for ten seconds to reboot. Audi: the update menu is **BACK + upper-left**
   button and needs developer mode switched on in the head unit (5F). To
   stop the card starting on its own, rename `Swdlautorun.txt` to
   `_Swdlautorun.txt` (see the
   [Install guide](docs/Install.md#route-1-software-update)).
3. **Use it.** Plug in the phone, start a map, and switch the cluster to its
   map view with the steering wheel buttons. iPhone: once after installing,
   **Forget This Car** in its CarPlay settings and plug it in again.

### Settings

You do not need to edit anything. In `ClusterMap/gal_dualscreen.conf` the
map's size (`GAL_SECONDARY_DPI`) and the area kept clear of the dials
(`GAL_SECONDARY_INSETS`) ship as `auto`. The installer reads which car it is
in and the size of the cockpit's map window, and uses the values owners have
tested on that car:

| Car | Cockpit map window | DPI | Insets (top, bottom, left, right) |
|---|---|---|---|
| SEAT | 1010×376 | 140 | `105,127,127,127` |
| Skoda | 1010×376 | 125 | `40,127,127,127` |
| VW | 800×480 | 138 | `52,82,127,127` |
| VW (Tiguan) | 1010×376 | 115, full frame | `102,52,127,127` |
| Any other | | 125 | `40,40,127,127` |

When owners of another car settle on values that work, they are added to
this list and arrive with the next release, so leave `auto` in place and
your car picks them up when you install it. To use your own values instead,
replace `auto` with numbers and install again; the installer keeps them.
The old 800×480 defaults are a good place to start:

```ini
GAL_SECONDARY_DPI=125
GAL_SECONDARY_INSETS=40,40,127,127
```

Lower DPI draws the map and its text smaller; raise an inset (0 to 127) if
something hides behind the dials.
`update_result.txt` says which values were used and where they came from.
Starting points from other owners are in the
[Install guide](docs/Install.md#settings-owners-have-settled-on).

Optional `CLUSTERMAP_720P=1` and `CLUSTERMAP_1080P=1` settings test Android
Auto streams at 1280×720 and 1920×1080, cropped to the cockpit window. The
car-tested Audi 1080p example for a 1440×455 window is:

```ini
CLUSTERMAP_1080P=1
GAL_PLAYER_DECODER=hw
GAL_PLAYER_NVSS_OUTPUT=1
GAL_SECONDARY_DPI=160
GAL_SECONDARY_INSETS=45,85,75,75
```

Hardware decode/output 1 is Audi-only: Skoda reports output 1 as `0x0`. See
the [install guide](docs/Install.md) for test-mode details.

The update writes what it did to `ClusterMap/update_result.txt` on the card.
It also adds a **ClusterMap** screen to the green engineering menu (hold MENU >
`Testmode` > `Green Developer Menu`): status, install, logs and uninstall on
the first screen, and three screens under it:

| Screen | What is there |
|---|---|
| `ClusterMapPicture` | Sharper map on/off, map always light / always dark / following the headlights (reboot after) |
| `ClusterMapOptions` | Hardware decoder on/off, keep the phone's map on/off (reconnect the phone), cluster map off/on (reboot after) |
| `ClusterMapSupport` | Files for porting, the turn-arrows switch, the hardware decoder check, performance figures in the log |

A switch changes one setting on the unit without editing the card, says
"already set" when there is nothing to change, and is kept by the next
install. The [Install guide](docs/Install.md#route-2-green-menu) has every entry.

The green menu and SSH routes, every setting, and recovery are in the
[Install guide](docs/Install.md).

**Uninstall:** green menu > `ClusterMap` > **Uninstall and restore original
state**, then reboot. Or, without the menu: on a computer, move
`UNINSTALL.txt` from the folder `to uninstall, move this file up one folder`
up into `ClusterMap`, and run the same update again.

## Which language should I write in?

Yours. Issues and comments in any language are welcome, and several cars now
working were debugged with people writing in their own. Logs and photos need
no translation at all. The same in nine languages:
[#36](https://github.com/MacsInSpace/mib-cluster-map/issues/36).

## Will it work on my car?

| Head unit | Firmware train starts | Today |
|---|---|---|
| VW Discover Pro 9.2 in (MIB2.5 High) | `MHI2_ER_VWG13_` | **Map** on `P4521` and `K4525` (software 1367), both road-tested, and `P4512` (Golf R; Passat B8, #47). US `P3662` installs as tested. `P4174` (Passat R wagon, #49) and `P4521_1` (Golf Alltrack) tested. `P3657` (Golf GTE, MU1077, #100): the CarPlay map works with Google Maps, Apple Maps and Waze, with the iPhone's route hidden from the car (on by itself there since v1.2.7); Android Auto installs since v1.2.6 but has not been tried with an Android phone, reports welcome. `P4512_2` music info works (#24), and a Passat B8 on `P4512_2` that showed "loading" runs cleanly since v1.2.7 switches the older renderer off (#24). Tiguans on `P4521` with the larger 1010×376 cockpit (#95, #137) show the map; set `CLUSTERMAP_FULL_FRAME=1` (or **Sharper map ON** in the green menu) so it fills the width. Others wanted |
| SEAT with the Harman unit | `MHI2_ER_SEG11_` | **Map** on `P4708` and `P4709` (1010×376 cluster window). **Arrows** on both |
| Skoda with the Harman unit | `MHI2_ER_SKG13_` | **Map** on `P4526` (#15) and `P4523` (#56), car-confirmed. Others wanted |
| VW Discover Pro 8 in (MIB2 High) | `MHI2_ER_VWG11_` | **Map** on `K3342` (MU1427), Passat B8, found and road-tested by owners (#39, #28), and `P3301` (#33); beta18 on K3342 confirmed in #64 and #65; a Tiguan on `K3342` that showed "loading" works since v1.2.7 switches the older renderer off (#105); wired CarPlay works on K3342 MU1427 (#62, #111; since v1.2.6 without a trial line, confirmed again on a clean v1.2.6 install), and #118 reports everything working there; CarPlay through an Otto Pico wireless adapter works too (#111). Turn and music info are not available on `K3342`: its interface differs from the one those jars were built for. `K3332` (Golf 7, MU1187) works since v1.2.3 (#45). Set `CLUSTERMAP_ADD_NAVIGNORE=1` to keep the map during an Android Auto route; with an iPhone leave it at 0, because CarPlay stops connecting while NavActiveIgnore is loaded on these units (#62, #106, #111). For CarPlay the installer hides the iPhone's route from the car instead (`CLUSTERMAP_CARPLAY_HIDE_NAV`, on by itself on these units since v1.2.6), which keeps the map on a route (#111). **`S2125`: update to `K3342` first** (see below); on S2125 itself NavActiveIgnore stopped Android Auto, so the map goes when a route starts |
| VW Discover Pro, Japan | `MHI2_JP_VW48x_` | **Trial** on `P0953`, which has the same Android Auto program as `P4708` and needs no trial line (#37), being tested |
| Audi MIB2 High, Harman/Tegra | `MHI2_ER_AU` | **Map** on the A4 B9 `K3346` (#14; 1440×455 cockpit window, context 72, both set by the installer; shown in the map view and the Audi's own cockpit view) and the Q5 FY `K3346` (#96, v1.2.1; an Audi NavActiveIgnore M.I.B. put there is left in place). A3/S3 8V `AU37x_P5089` (#51), `P5153` (#63) and `P4203` (#81, v1.2.4) work. A7 C7.5 `AU57x_K3663`: Android Auto and CarPlay on the cockpit (context 73, set by the installer; its CarPlay library, 694088 bytes, is accepted without a trial line since v1.2.1). The US A7 C7.5 `MHI2_US_AU57x_K3341` works with Android Auto too (same window and context; the map stays on a route with the Audi NavActiveIgnore, which the installer adds; CarPlay not tried). The A6 C7.5 has the same firmware, and Android Auto works there too (#68; a 2016 facelift out of the box on v1.2.1; #114 and another A7 C7.5 `K3663_1`, #140, on v1.2.6; an A6 Avant C7.5 `K3663_1` with CarPlay too, #147). With the Audi NavActiveIgnore, a CarPlay route (Waze) stays on the A7's cockpit. On the A7, the steering-wheel roller zooms the CarPlay map ([CarPlay](docs/CarPlay.md#steering-wheel-zoom-audi-a6a7-c75)); the installer adds the Audi build of NavActiveIgnore there (M.I.B.'s; the toolbox's VW build does not fit this unit). An RS3 is still to be tried. The pre-facelift A6 C7 `AU57x_P3236` is not supported yet: a trial line from its files is being tried (#127, #122). `AU57x_P3634` (A6 C7) is not supported, but its owner updated the unit to `K3663_1` and everything works there (#142); the same may suit `P3236`. The update needs developer mode (see Install) |
| Audi MIB2 High, Qualcomm | `MHI2Q_` | Not this project: see [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay) |
| MIB2 Standard (Composition, Discover Media) | `MST2_` | No. A different unit; nothing here applies |

**VWG11 on `S2125`:** update the unit to `MHI2_ER_VWG11_K3342` (MU1427)
through a VW dealer or a firmware package you trust (owners have used
`MHI2_ER_VWG11_K3342_1_AIO_MU1427`), check the train and MU in the green menu
afterwards, then install. Updating firmware is at your own risk; this project
doesn't host or link firmware. If you already had NavActiveIgnore from M.I.B.,
use the stock `gal.json` (#28).

You need a digital cluster (Active Info Display) for the map. The train is on
the green menu **Status** screen; "Software: 1367" under `Setup` > `System
information` is a hint, not proof. You do not have to work it out: the
installer checks the real firmware itself.

Not listed, or "wanted"? Run the update anyway: it installs nothing and
collects what is needed to add your unit. The quickest way to get it working
is to port it yourself with those files: see
[Port your own car](CONTRIBUTING.md#port-your-own-car).

## Limitations

The cockpit shows the picture the phone makes for a second display. The car
side only offers that display and plays what arrives: it draws nothing of its
own and cannot change what an app sends. Most questions that come back are one
of these:

- **Which apps show a map.** Each app decides whether it draws on the cockpit.
  Google Maps, Waze and Yandex do. Yanosik, TomTom and Mapy.com send only
  their icon, and opening one of them on the centre screen replaces the map on
  the cockpit with that icon (#120, #123, #107). Only the app's makers can
  change that.
- **Day and night colours.** Google Maps follows the car. Waze stays dark on
  the cockpit whatever the centre screen shows (#129, #40).
- **What is on the map.** Alerts, speed limits, the turn card and the arrival
  card are the app's. Waze shows no alerts on the cockpit (#128). You can
  change the size (`GAL_SECONDARY_DPI`) and the area the app keeps clear
  (`GAL_SECONDARY_INSETS`), not the content. At a high DPI Google Maps drops
  its arrival card.
- **Zoom.** Android Auto has no zoom for the cockpit map; the steering-wheel
  roller only changes the car's own hidden map. With CarPlay the roller zooms
  on the Audi A6/A7 C7.5.
- **Wireless adapters.** A cable always gives the most. Many wireless CarPlay
  adapters never ask the car for the cockpit picture
  ([CarPlay](docs/CarPlay.md#wireless-adapters)). Some Android Auto adapters
  stop working when the car offers a second display: with a SmartBox-D824 the
  centre screen stayed black (#101). What fixed it there: in Android Auto's
  developer settings on the phone, allow only the 800x480 video resolution;
  then the adapter worked with both screens. Otherwise use a cable, or switch
  the cockpit map off (green menu, `ClusterMapOptions` > **Cluster map OFF**)
  to have Android Auto as before. AAWireless (including TWO) and a Motorola
  MA1 are reported working.
- **The car's own overlays.** Lines the cockpit draws over its map, such as
  the street name bar on an Audi A6/A7, stay there (#126). Raise the bottom
  inset so the app keeps that strip clear.
- **Smoothness.** The picture is decoded in software at up to 30 pictures a
  second, 800×480. It will not match the centre screen.
- **Arrival time and lanes in the dials.** The car's own guidance screens are
  not fed; with `CLUSTERMAP_TURN_INFO=1` VW, SEAT and Skoda get the arrow,
  distance and road name. Audi has no such jar.

## Where the project stands

The project began with one Golf, and that car has worked for a while. It now
reaches VW, SEAT, Skoda and Audi units thanks to owners who sent logs and
photos from their own cars. It is still maintained, but by one person with
a day job, so replies come a few times a week rather than daily, and
releases come when something is confirmed on a car.

What would help most now is people who work on the code directly: port your
own firmware in a fork (an AI assistant makes this far more approachable than
it sounds), fix what you find, and send a pull request. The
[Contributing guide](CONTRIBUTING.md) explains how, including a
step-by-step for porting your own car.

## Status

Experimental. Developed on a VW Golf 7.5 (`P4521`) and tested on a Tiguan (`P4521`),
a Passat and an Arteon (`K4525`), two SEATs (`P4708`, `P4709`), a Skoda (`P4526`),
a Golf R and a Passat B8 (`P4512`). The Android Auto map runs at about 30 frames
per second, with and without a route, and comes back by itself after the
phone is unplugged and plugged in again.

| Part | State |
|---|---|
| Android Auto map, installer and uninstaller over SSH | Tested on cars (Golf `P4521`, SEAT `P4708`) |
| Software update and green menu routes | Tested on cars (Golf `P4521`, Golf R `P4512`) |
| Hardware video decoding (`GAL_PLAYER_DECODER=hw`; the default on `P4521`, and on `K4525` from the next release; off elsewhere) | Works on a Golf (`P4521`): 30 pictures a second at about a third of the processor time, also through a wireless adapter. Also on an Arteon/Passat `K4525` (#135; on by default there from the next release). Other cars: run **Hardware decoder check** in `ClusterMapSupport` and report what it says. Audi A3 8V 1080p (`CLUSTERMAP_1080P=1`) car-tested with the draw-to-display method (`GAL_PLAYER_NVSS_OUTPUT=1`, #125) |
| CarPlay map | Shown on a car (Golf R, iPhone over USB) after a firewall fix; layout between the dials under test |
| Long drives, reverse camera, waking from sleep | Road-tested on `K4525`; otherwise little testing |
| Autorun install without the service menu (`Swdlautorun.txt`, on by default) | Tested on a car (Golf `P4521`); Audi untested |

Showing the arrows and the map together works on SEAT with
`CLUSTERMAP_KEEP_ARROWS=1`. On VW leave it at 0: the map has gone blank when
a route starts, and on a Golf (`P4521`) the cockpit switched to its own arrow
view after a few presses of OK and stayed there, even after a restart, until
the arrows were removed. One Tiguan (`K4525`) reports both working (#44). The
turn pictograms need `GAL_DUALSCREEN_AAP_MINOR` at 5 or lower, the shipped
value from v1.1.1-beta9 (#4); the hook now translates the newer navigation
messages, so 6 and 7 should work too, still to be tested on a car. Not possible so far: zooming the cluster map from the steering
wheel ([why](docs/Development.md#zoom)), and switching between the phone's map
and the car's map from the steering wheel.

## Documentation

| Page | For |
|---|---|
| [Install guide](docs/Install.md) | Install routes, the menu, settings, logs, safety and recovery, getting your unit added |
| [CarPlay](docs/CarPlay.md) | The CarPlay map: design, status, testing |
| [Development](docs/Development.md) | How it works, what was learned, adding a firmware, building |
| [Contributing](CONTRIBUTING.md) | Forks, pull requests, using an AI assistant, and porting your own car |

## Reporting a problem

Open an issue with your car, firmware train, what you did and what you saw.
Attach `update_result.txt` and the logs from green menu **Save logs to SD**,
saved before rebooting: without them most reports can't be looked into.
A fix of your own is even better, as a pull request.
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
  included from source under GPL-3.0; the A7's steering-wheel zoom follows
  aberbic's (`changeMapZoomLevel` over loopback UDP).
- **Mr-MIBonk** ([M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)):
  the `Swdlautorun.txt` trigger for installing without the service menu, and
  harman-f's Audi build of `NavActiveIgnore.jar` from it, bundled unmodified
  under `thirdparty/navactiveignore-audi/` (GPL-2.0) for the A6/A7 C7.5.
- **AMDFX60** ([Skoda fork](https://github.com/AMDFX60/mib-cluster-map)):
  the sharper-map full-frame mode, the fix for insets above 127 and the
  player priority setting, car-tested on his Superb and merged back here.
- **kkrvch** ([mib-std2-kombibridge](https://github.com/kkrvch/mib-std2-kombibridge)):
  the Android Auto 1.7 navigation decoder for MIB2 Standard. Its message
  layout and manoeuvre table are ported into `src/nav_translate.c`, with the
  author's kind permission, so the turn arrows can survive newer Android Auto
  versions. Thank you!
- **lito69**, **tulio150** and **DaniFR3**: car tests and porting files for
  the SEAT and the settings. Thanks also to lito69 for finding kombibridge and
  pointing us to it.
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
