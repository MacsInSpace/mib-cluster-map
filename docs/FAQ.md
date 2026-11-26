# Frequently asked questions

Click a question to open it. Not answered here? Open an
[issue](https://github.com/MacsInSpace/mib-cluster-map/issues) with your car, firmware train and
`update_result.txt`, and a Save logs zip if something is broken.
Write in your own language if that is easier ([Language note](#language-note)).

Asking for a feature? [Features](Features.md) lists what is done, what is on
the to-do list, what the phone or the car can't provide, and what is not
planned.

- [Your car](#your-car)
- [Installing and updating](#installing-and-updating)
- [When something is wrong](#when-something-is-wrong)
- [What it can and cannot do](#what-it-can-and-cannot-do)
- [CarPlay](#carplay)
- [The project](#the-project)
- [Language note](#language-note)

## Your car

<details>
<summary><a id="supported"></a><b>Is my car supported?</b></summary>

You need a **Harman MIB2 or MIB2.5 High** head unit ("Discover Pro") and a
**digital cluster** (Active Info Display / Virtual Cockpit). What decides it
is the unit's **firmware train**, such as `MHI2_ER_VWG13_P4521` (see the next
question). You do not have to work it out before trying: the installer checks
the real firmware itself and installs only what fits, or nothing.

| Head unit | Train starts with | Android Auto map | CarPlay map |
|---|---|---|---|
| VW Discover Pro 9.2 in (MIB2.5 High) | `MHI2_ER_VWG13_`, `MHI2_US_VWG13_` | `P4521`, `K4525`, `P4512`, `P4174`, US `P3662` | `P4512`, `K4525`, `P4521`, `P3657` |
| VW Discover Pro 8 in (MIB2 High) | `MHI2_ER_VWG11_` | `K3342`, `K3332`, `P3301` (`S2125`: update to `K3342` first) | `K3342`, `K3332` |
| SEAT with the Harman unit | `MHI2_ER_SEG11_` | `P4708`, `P4709`, and the arrows on both | `P4709` |
| Skoda with the Harman unit | `MHI2_ER_SKG13_` | `P4526`, `P4523` | `P4526` |
| Audi MIB2 High, Harman/Tegra | `MHI2_ER_AU`, `MHI2_US_AU` | A4 B9 / Q5 FY `K3346`, A3/S3 8V `P5089`, `P5153`, `P4203`, A6/A7 C7.5 `K3663`, `P3236`, `P3634`, US A7 `K3341`; Q2 `P3243` installs (CarPlay map seen with the trial line; 1440×455 window since v1.2.12) | A6/A7 C7.5 `K3663`, US `K3341`, `P3327`, `P3237` |
| Audi A6L/A7 C7.5, China | `MHI2_CN_AU57x_` | | `K1006_2` (with the steering-wheel zoom) |
| VW Discover Pro, Japan | `MHI2_JP_VW48x_` | Trial on `P0953` | |
| Audi MIB2 High, Qualcomm | `MHI2Q_` | Not this project: see [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay) | |
| MIB2 Standard (Composition, Discover Media) | `MST2_` | No. A different unit; nothing here applies | |

CarPlay needs the iPhone's CarPlay library on the unit to be a build the
CarPlay map knows; the installer checks it and says so in
`update_result.txt`. `P3657` has the CarPlay map but Android Auto there is
untried.

The details per make are below.

<details>
<summary>VW Discover Pro 9.2 in (MIB2.5 High), <code>MHI2_ER_VWG13_</code></summary>

- **`P4521`** and **`K4525`** (software 1367): map, both road-tested.
  `P4521_1` (Golf Alltrack) tested.
- **`P4512`**: Golf R; Passat B8 (#47). A Tiguan on `P4512_1` (MU1161):
  map, turn info, ETA, HUD arrows, music and cover art, through an Ottocast
  wireless adapter (discussion #197). `P4512_2` music info works (#24),
  and a Passat B8 on `P4512_2` that showed "loading" runs cleanly since
  v1.2.7 switches the older renderer off (#24).
- **`P4174`**: Passat R wagon (#49).
- **US `P3662`**: installs as tested.
- **`P3657`** (Golf GTE, MU1077, #100): the CarPlay map works with Google
  Maps, Apple Maps and Waze, with the iPhone's route hidden from the car (on
  by itself there since v1.2.7). Android Auto installs since v1.2.6 but has
  not been tried with an Android phone: reports welcome.
- **Tiguans on `P4521`** with the larger 1010×376 cockpit (#95, #137) show
  the map; set `CLUSTERMAP_FULL_FRAME=1` (or **Sharper map ON** in the green
  menu) so it fills the width.
- Other VWG13 trains: wanted.

</details>

<details>
<summary>VW Discover Pro 8 in (MIB2 High), <code>MHI2_ER_VWG11_</code></summary>

- **`K3342`** (MU1427), Passat B8, Passat GTE, Tiguan: found and
  road-tested by owners (#39, #28; beta18 confirmed in #64 and #65). A
  Tiguan on `K3342` that showed "loading" works since v1.2.7 switches the
  older renderer off (#105).
  - Wired CarPlay works (#62, #111, #209; without a trial line since v1.2.6),
    and #118 reports everything working. CarPlay through an Ottocast Mini
    Pico wireless adapter works too (#58, #111), and another in #209.
  - Track and turn info install on `K3342` since v1.2.9, as builds made for
    its own interface. Android Auto track info is car-tested on two Passats
    (#62); with CarPlay the cockpit's media page shows the new title only
    when you go back into it, which is being worked on (#62). Turn info:
    reports welcome (#65).
  - Set `CLUSTERMAP_ADD_NAVIGNORE=1` to keep the map during an Android Auto
    route. With an iPhone leave it at 0: CarPlay stops connecting while
    NavActiveIgnore is loaded on these units (#62, #106, #111). For CarPlay
    the installer hides the iPhone's route from the car instead
    (`CLUSTERMAP_CARPLAY_HIDE_NAV`, on by itself since v1.2.6), which keeps
    the map on a route (#111).
- **`K3332`** (Golf 7, MU1187): works since v1.2.3 (#45).
- **`P3301`**: works (#33).
- **`S2125`**: update to `K3342` first (see *My firmware is older*). On S2125
  itself NavActiveIgnore stopped Android Auto, so the map goes when a route
  starts.

</details>

<details>
<summary>SEAT, <code>MHI2_ER_SEG11_</code></summary>

- **`P4708`** and **`P4709`**: map (1010×376 cluster window) and arrows.

</details>

<details>
<summary>Skoda, <code>MHI2_ER_SKG13_</code></summary>

- **`P4526`** (#15) and **`P4523`** (#56): map, car-confirmed. The CarPlay
  map works on `P4526` too, with Waze (#146).
- Others wanted.

</details>

<details>
<summary>Audi (Harman/Tegra), <code>MHI2_ER_AU</code></summary>

The update menu needs developer mode on Audi (see the
[Install guide](Install.md#route-1-software-update)).

- **A4 B9 `K3346`** (#14): 1440×455 cockpit window, context 72, both set by
  the installer; shown in the map view and the Audi's own cockpit view.
- **Q5 FY `K3346`** (#96, v1.2.1): an Audi NavActiveIgnore that M.I.B. put
  there is left in place.
- **A3/S3 8V `AU37x_P5089`** (#51), **`P5153`** (#63) and **`P4203`** (#81,
  v1.2.4) work, and an RS3 on `P5089` (#192). Since v1.2.12 `P5089` gets
  NavActiveIgnore (the map stays on a route: #190, #192), 1080p and the
  hardware decoder by itself, and since v1.2.13 `P5153` too (1080p
  car-tested there, #155; NavActiveIgnore, #110). Android Auto cover art and playback time on the
  cockpit: `CLUSTERMAP_AU37X_COVER=1` (#195, opt-in).
- **A7 C7.5 `AU57x_K3663`**: Android Auto and CarPlay on the cockpit
  (context 73, set by the installer; its CarPlay library is accepted without
  a trial line since v1.2.1). With the Audi NavActiveIgnore, which the
  installer adds (M.I.B.'s build; the toolbox's VW build does not fit this
  unit), a CarPlay route (Waze) stays on the cockpit. The steering-wheel
  roller zooms the CarPlay map ([CarPlay](CarPlay.md#steering-wheel-zoom-audi-a6a7-c75)).
- **RS7 C7.5 `AU57x_K3663`**: CarPlay on the cockpit once the nav tab is put
  in map view while the CarPlay map is up (`ClusterMapGfxKeep.jar`, added by
  the installer): its tab was on the compass, or the route map during an
  Audi route, and showed the compass or a blank tab
  ([CarPlay](CarPlay.md#cockpit-map-view-audi-a6a7-c75)).
- **A6 C7.5** has the same firmware and works too (#68; a 2016 facelift out
  of the box on v1.2.1; #114 and another A7 `K3663_1`, #140, on v1.2.6; an
  A6 Avant C7.5 `K3663_1` with CarPlay too, #147; a 2015 A6 `K3663_1`
  with CarPlay through an Ottocast wireless adapter, discussion #135).
- **US A7 C7.5 `MHI2_US_AU57x_K3341`** works with Android Auto (same window
  and context; the map stays on a route with the Audi NavActiveIgnore, which
  the installer adds; CarPlay not tried).
- **A6/A7 C7.5 `AU57x_P3236`** works since v1.2.11: the map stays on the
  cockpit through Google Maps routes with the Audi NavActiveIgnore, which the
  installer adds (#127). CarPlay not tried yet.
- **US A6/A7 C7.5 `AU57x_P3237`**: the CarPlay map works, with the iPhone's
  route hidden from the car as on `P3327` (#176). Android Auto not tried yet.
- **A6 C7.5 `AU57x_P3634`**: supported since v1.2.13 (the map on the cockpit
  with the trial line on #158; the same program on #204). Another owner
  updated the unit to `K3663_1` instead, and everything works there (#142).

</details>

<details>
<summary>VW Discover Pro, Japan, <code>MHI2_JP_VW48x_</code></summary>

- **`P0953`**: trial. It has the same Android Auto program as `P4708` and
  needs no trial line (#37); being tested.

</details>

</details>

<details>
<summary><a id="other-units"></a><b>I have MIB3, MIB2 Standard (Discover Media, Composition), a Delphi or TechniSat unit, or MH2P. Will it work?</b></summary>

No, and it isn't planned. This project runs only on the Harman MIB2 and
MIB2.5 **High** units, whose firmware train starts with `MHI2_`. The others
are different platforms with different software inside:

- **MIB2 Standard** (`MST2_...`: Discover Media, Composition, the TechniSat,
  Preh and Delphi units): try
  [xPaiiN/mst2-carplay-vc](https://github.com/xPaiiN/mst2-carplay-vc) or
  [1mikew/mst2-altscreen-carplay](https://github.com/1mikew/mst2-altscreen-carplay)
  (CarPlay on the cockpit), and
  [kkrvch/mib-std2-kombibridge](https://github.com/kkrvch/mib-std2-kombibridge)
  (Android Auto turn info). We can't vouch for them.
- **MIB3** (about 2020 on; for example Audi software 4572, MMI `3D.28`): no.
- **MH2P** (Porsche, newer Audi): no (#138).
- **Audi Qualcomm MIB2 High** (`MHI2Q_`): see
  [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay).

If the update on the SD card is refused with "Release info can't be read" or
"Section common already exists", the unit is one of these (#117).

</details>

<details>
<summary><a id="analogue-cluster"></a><b>My car has analogue dials, or a cockpit without a map. Will it work?</b></summary>

It needs a cluster screen that can show the **car's own navigation map**:
the phone's map goes into that window.

- **A colour display between analogue dials that shows the car's map**
  works. The Audi A6/A7 C7.5 is the example: its 800×298 window takes the
  map.
- **A small display that only shows arrows** (the small screen between the
  dials on many VWs, SEATs and Skodas, or a monochrome one) has no map
  window, so the map can't go there (#46). For arrows there, see
  [adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc)
  (Android Auto) or
  [chrzanowy/mhi2-aid-carplay](https://github.com/chrzanowy/mhi2-aid-carplay)
  (CarPlay).
- **A digital cockpit in a car without factory navigation** may never show a
  map from the head unit; one 790 B cockpit didn't (#52).

Not sure? Run the update with `COLLECT.txt` (see
[Install](Install.md#route-1-software-update)): it changes nothing, and the
files it collects in `ClusterMap/` show whether the cockpit has a map window.
Attach them to a new issue and we'll look.

</details>

<details>
<summary><a id="aftermarket-box"></a><b>I use an aftermarket CarPlay or Android Auto box. Will it work?</b></summary>

- **A box on the screen's cable** (an LVDS interface such as an AUTOABC
  CX301, which runs CarPlay itself and switches the screen): no. The head
  unit never has a phone session for the cluster map to use (#172).
- **A box that pretends to be an iPhone**, such as a Carlinkit CPC200-Tbox:
  no. It never asks the car for the cockpit picture (#55).
- **A wireless adapter** that passes the phone through to the car's own
  CarPlay or Android Auto: often yes. See
  [It stopped working with a wireless adapter](#wireless-adapter).

</details>

<details>
<summary><a id="retrofit"></a><b>My head unit is a retrofit, or a unit converted from another region. Is that OK?</b></summary>

Yes. Owners run it on retrofitted and converted units (#131, #48). What
counts is the train the unit reports, which the installer reads, and the MOST
fibre (the orange optical cable) between the head unit and the cluster,
which has to be connected for the cockpit to show any map from the head unit.

</details>

<details>
<summary><a id="find-train"></a><b>How do I find my firmware train?</b></summary>

After installing, the green menu **Status** screen shows it (hold MENU >
`Testmode` > `Green Developer Menu` > `ClusterMap`). It is also the first
thing in `ClusterMap/update_result.txt` after any install attempt, even one
that installed nothing. "Software: 1367" under `Setup` > `System information`
is a hint, not proof: two cars with the same number can have different
trains.

</details>

<details>
<summary><a id="add-my-car"></a><b>My car is not listed, or says "wanted". Can you support it?</b></summary>

Run the update anyway. On a unit it does not know, it installs nothing and
collects the files needed to add it (`ClusterMap/porting_<train>/`). Then
either:

- **Port it yourself** with those files, which is the quickest way: see
  [Port your own car](../CONTRIBUTING.md#port-your-own-car). An AI assistant
  makes this far more approachable than it sounds.
- **Send the files**: attach the zipped folder to an issue, or email it to
  RS3WGN@gmail.com. A new unit needs a car test before it is called
  supported, so expect a trial line to try first.

</details>

<details>
<summary><a id="older-firmware"></a><b>My firmware is older. Should I update it first?</b></summary>

Sometimes that is the shortest way:

- **VWG11 `S2125`**: update the unit to `MHI2_ER_VWG11_K3342` (MU1427)
  through a VW dealer or a firmware package you trust (owners have used
  `MHI2_ER_VWG11_K3342_1_AIO_MU1427`), check the train and MU in the green
  menu afterwards, then install. If you already had NavActiveIgnore from
  M.I.B., use the stock `gal.json` (#28).
- **Audi A6 C7.5 `P3634`**: supported as it is since v1.2.13; one owner
  updated to `K3663_1` instead, and everything worked (#142).

Updating firmware is at your own risk; this project does not host or link
firmware.

</details>

## Installing and updating

<details>
<summary><a id="first-install"></a><b>What do I need to set before the first install?</b></summary>

Nothing. Copy the release onto a FAT32 SD card and run the update (see the
[Install guide](Install.md)). The map's size and position ship as `auto` and
the installer fills in the values owners of your car have tested.

Extras such as track info or turn arrows in the dials are **off** until you
switch them on, because each one is only known to work on some cars.
[Features](Features.md) says which ones exist and where; `update_result.txt`
says whether one was added on your car.

</details>

<details>
<summary><a id="usb"></a><b>Can I install from a USB stick instead of an SD card?</b></summary>

Yes. Since v1.2.5 the green menu's scripts follow the card or stick the
install ran from (#109). Keep using the same one for the green menu.

</details>

<details>
<summary><a id="update-loop"></a><b>The update keeps starting again by itself</b></summary>

The card still has `Swdlautorun.txt`, which starts the update whenever the
unit sees the card, and the install didn't get to its end to switch that
off (#150, #163). On a computer, rename it to `_Swdlautorun.txt`, then start
the update from the menu (hold MENU > `Software updates/versions` >
`Update`) and let it finish. `ClusterMap/update_result.txt` then says what
happened.

</details>

<details>
<summary><a id="version-compare"></a><b>A screen says "Version back documentation" or "Connect diagnostic tester"</b></summary>

That is a normal step of every SD update. Press **Cancel**; the unit
restarts once more (#114, #196). The steps, with the module list before it,
are in the [Install guide](Install.md#route-1-software-update).

</details>

<details>
<summary><a id="fault-code"></a><b>The head unit has a fault code after the update (B201A00 in 5F)</b></summary>

Any software update from SD can log `B201A00 Check Software Version
Management` in the head unit, even one that installs nothing, and
uninstalling doesn't clear it. CarPlay, Android Auto and other activations
keep working. More in the [Install guide](Install.md#fault-b201a00).

</details>

<details>
<summary><a id="setting-ignored"></a><b>I changed a setting, but nothing changed</b></summary>

Check these, in this order:

1. The line must not start with `#`. Remove the `#` at the very start.
2. **Install again** after saving the file, then reboot. Editing the card
   alone changes nothing on the unit.
3. The file must still be called `gal_dualscreen.conf`. Windows hides file
   endings and some editors save it as `gal_dualscreen.conf.txt`; if
   `update_result.txt` says `no gal_dualscreen.conf beside this script`, that
   is what happened (discussion #161). Turn on "File name extensions" in
   Explorer's View menu and rename it.
4. Some settings only exist on some cars: `update_result.txt` says what was
   used and what was skipped.

</details>

<details>
<summary><a id="update"></a><b>How do I update to a new version?</b></summary>

Install it over the old one; there is no need to uninstall first. Replace the
files on the SD card with the new release (the `ClusterMap` folder,
`Custom`, `metainfo2.txt`, `Swdlautorun.txt`), run the update as the first
time, then reboot. The lines you changed in `gal_dualscreen.conf` last time
are remembered and put back; set `CLUSTERMAP_KEEP_SETTINGS=0` for a clean
install.

</details>

<details>
<summary><a id="change-setting"></a><b>Where do I change a setting?</b></summary>

Two places:

- **The green menu** (hold MENU > `Testmode` > `Green Developer Menu` >
  `ClusterMap`) has switches for the common ones: sharper map, light/dark,
  hardware decoder, keep the phone's map, cluster map off. A switch changes
  the unit directly and is kept by the next install.
- **Everything else** is a line in `ClusterMap/gal_dualscreen.conf` on the SD
  card. Remove the `#` at the very start of the line, change the value, save,
  and **install again** (then reboot). Editing the file alone changes
  nothing on the unit.

Every setting is explained on the [Settings](Settings.md) page, grouped by
what it fixes.

</details>

<details>
<summary><a id="why-settings"></a><b>Why are there so many settings?</b></summary>

Because the cars differ. The cockpit's map window is 800×480 on most VWs,
1010×376 on SEAT and Skoda, 1440×455 on many Audis and 800×298 on the A6/A7,
with different dials around it. Android Auto and CarPlay size their text and
cards from numbers the car gives them, and those have to be tuned per cockpit
on the road. Some fixes help one car and break another, and new features stay
off until owners have tested them.

You don't need to touch them: most ship as `auto`, which the installer fills
in with the values owners of your car have tested. The
[Settings](Settings.md) page explains each one, grouped by what it fixes.

</details>

<details>
<summary><a id="map-size"></a><b>Do I need to change the map size or insets?</b></summary>

No. `GAL_SECONDARY_DPI` (the map's size) and `GAL_SECONDARY_INSETS` (the area
kept clear of the dials) ship as `auto`: the installer reads which car it is
in and the size of the cockpit's map window, and uses the values owners have
tested on that car. When owners of another car settle on values, they become
that car's `auto` in the next release.

To use your own, replace `auto` with numbers and install again; the installer
keeps them. Lower DPI draws the map and its text smaller; raise an inset (0
to 127) if something hides behind the dials. `update_result.txt` says which
values were used. Values owners have used are in the
[Install guide](Install.md#settings-owners-have-settled-on).

</details>

<details>
<summary><a id="hd-decoder"></a><b>What do 720p, 1080p and the hardware decoder do?</b></summary>

By default Android Auto sends 800×480, decoded in software at up to 30
pictures a second.

- **Hardware decoder** (`GAL_PLAYER_DECODER=hw`, or **Hardware decoder ON**
  in `ClusterMapOptions`): the same picture at about a third of the
  processor time. On by default on `P4521`, `K4525` and the Audi A3 8V
  `P5089`. Elsewhere, run **Hardware decoder check** in `ClusterMapSupport`
  first and report what it says.
- **`CLUSTERMAP_720P=1` / `CLUSTERMAP_1080P=1`**: test settings that ask for
  a 1280×720 or 1920×1080 stream, cropped to the cockpit window. Only worth
  it on the larger 1440×455 Audi cockpits; a 1010×376 cockpit gains nothing
  from 1080p. On the A3 8V `P5089` 1080p is on by default, with its own DPI
  and insets; elsewhere the DPI and insets stay the 800×480 ones, so set your
  own. The car-tested Audi 1080p example is in the
  [Install guide](Install.md#settings-owners-have-settled-on).

</details>

<details>
<summary><a id="uninstall"></a><b>How do I uninstall?</b></summary>

Green menu > `ClusterMap` > **Uninstall and restore original state**, then
reboot. Without the menu: on a computer, move `UNINSTALL.txt` from the folder
`to uninstall, move this file up one folder` up into `ClusterMap`, and run
the same update again. What it restores is in the
[Install guide](Install.md#what-the-installer-changes).

</details>

## When something is wrong

<details>
<summary><a id="map-goes-on-route"></a><b>The map shows, then goes when a route starts</b></summary>

The car's navigation takes the cockpit back as soon as the phone starts a
route, unless **NavActiveIgnore** is loaded. The installer adds it on the
trains where it is known to work. On others, `update_result.txt` says it is
not loaded: put `CLUSTERMAP_ADD_NAVIGNORE=1` in `gal_dualscreen.conf` and
install again. On VW Discover Pro 8 in with an iPhone, leave it off (see
*Is my car supported?* > VW 8 in).

</details>

<details>
<summary><a id="loading"></a><b>The cockpit says "loading", or the car's own map keeps coming back</b></summary>

Every car that showed this (#105, #24) also had an older cluster renderer
from another project installed (VcMOSTRenderMqb, `/navigation/opengl-render-qnx`),
which takes the same window. v1.2.7 switches it off at install. Install
v1.2.7 or later and reboot.

</details>

<details>
<summary><a id="send-logs"></a><b>It doesn't work. How do I send logs?</b></summary>

Straight after it happens, before rebooting: green menu > `ClusterMap` >
**Save logs to SD**. It writes a numbered folder in `ClusterMap/run_logs/`.
Zip that folder with `ClusterMap/update_result.txt` and attach it to your
issue on the GitHub website, with your car, train, what you did and what you
saw, and a photo if it helps.

- **Replying to a GitHub email does not carry attachments**: attach on the
  website, or email them to RS3WGN@gmail.com.
- Read them first: the system log can contain phone names and Bluetooth
  addresses.

More in the [Install guide](Install.md#if-it-does-not-work).

</details>

<details>
<summary><a id="wireless-adapter"></a><b>It stopped working with a wireless adapter</b></summary>

A cable always gives the most. Many wireless CarPlay adapters never ask the
car for the cockpit picture ([CarPlay](CarPlay.md#wireless-adapters)). Some
Android Auto adapters stop working when the car offers a second display: with
a SmartBox-D824 the centre screen stayed black (#101). What fixed it there:
in Android Auto's developer settings on the phone, allow only the 800x480
video resolution. Otherwise use a cable, or switch the cockpit map off (green
menu, `ClusterMapOptions` > **Cluster map OFF**) to have Android Auto as
before. AAWireless (including TWO) and a Motorola MA1 are reported working.

**A wireless CarPlay adapter that stops working after the install** (#196,
#207): add `CLUSTERMAP_CARPLAY=0` to `gal_dualscreen.conf` and install
again. CarPlay then stays stock, so the adapter works, and the Android Auto
map stays; only the CarPlay map on the cockpit goes. Reported working with
the CarPlay map: Ottocast (Otto) Mini Pico (#58, #111), Carlinkit 5.0
(#176) and the adapter in #209. Reported not working: TrolinkTek 4 (#207).

</details>

## What it can and cannot do

The cockpit shows the picture the phone makes for a second display. The car
side only offers that display and plays what arrives: it draws nothing of its
own and cannot change what an app sends.

<details>
<summary><a id="apps"></a><b>Which apps show a map?</b></summary>

Each app decides whether it draws on the cockpit. With Android Auto, Google
Maps, Waze and Yandex Maps do; with CarPlay, Apple Maps, Google Maps and Waze
do. TomTom draws there once a route is running (#123). Yanosik, Mapy.com, 2GIS and Yandex Navi send only
their icon, and opening one of them on the centre screen replaces the map on
the cockpit with that icon (#120, #107, #167, #185). Only the app's makers
can change that.

The cockpit always shows the navigation app that is in front: Google Maps on
the cockpit with another app on the centre screen isn't possible (#107,
#116). A media app that registers as navigation, such as Fermata, takes the
cockpit too, without a picture (#76).

</details>

<details>
<summary><a id="speed-limits"></a><b>Can it show speed limits, speed cameras or Waze alerts?</b></summary>

No. These are all decided by the phone or the car:

- **Speed limit:** Android Auto doesn't send one to the car at all (#32).
  With CarPlay the iPhone may draw one on the cockpit map itself; Apple Maps
  does where it has the data (#159). The speed-limit sign the cockpit shows
  on its own comes from the car's camera and map, and is coded with VCDS, not
  here (#132).
- **Speed cameras, police, hazards, traffic bubbles:** Waze and Google Maps
  leave them out of the picture they draw for the cockpit (#57, #98, #133,
  discussion #202). Only Waze can change that; a request from owners to Waze
  helps.
- **Current speed or other car data over the map:** not planned (#187).

</details>

<details>
<summary><a id="carplay-home"></a><b>Can the cockpit show CarPlay's home screen, music or video?</b></summary>

No. The cockpit shows the map picture the phone makes for a second screen.
CarPlay and Android Auto don't send their home screen or video there.
Playing video on the driver's display is not something this project will do.
Track info goes to the cockpit's own media page instead (see
[Can the cockpit show the song playing?](#music-info)).

</details>

<details>
<summary><a id="map-content"></a><b>Can I change what is on the map, or its colours?</b></summary>

- **Content**: alerts, speed limits, the turn card and the arrival card are
  the app's. Waze shows no alerts on the cockpit (#128). You can change the
  size (`GAL_SECONDARY_DPI`) and the area the app keeps clear
  (`GAL_SECONDARY_INSETS`), not the content. At a high DPI Google Maps drops
  its arrival card.
- **Layers and cards**: satellite view (#63, #175), Google Maps' arrival
  time (#154) and Waze's second manoeuvre (discussion #202) are the app's
  choice for the cockpit picture. Apple Maps on CarPlay does show the
  arrival time.
- **Day and night**: Google Maps follows the car. Waze stays dark on the
  cockpit whatever the centre screen shows (#129, #40). The green menu can
  force light or dark (`ClusterMapPicture`).
- **The car's own overlays**: lines the cockpit draws over its map, such as
  the street name bar on an Audi A6/A7, stay there (#126). Raise the bottom
  inset so the app keeps that strip clear.

</details>

<details>
<summary><a id="zoom"></a><b>Can I zoom the cockpit map?</b></summary>

Not with Android Auto: it has no zoom for the cockpit map, and the
steering-wheel roller only changes the car's own hidden map
([why](Development.md#zoom)).

With CarPlay the roller zooms the map on the Audi A6/A7 C7.5 (`K3663`, and
the Chinese `K1006_2`). On the US `K3341` it is a trial since v1.2.13:
`CLUSTERMAP_CARPLAY_WHEEL_ZOOM=1` (#156). On VW, SEAT and Skoda the
roller's keys don't reach the part of the unit this project can change, so
there it needs research first (#186, discussion #193). Some apps (Waze, some
Chinese apps) don't follow the zoom at all.

</details>

<details>
<summary><a id="switch-map"></a><b>Can I switch between the phone's map and the car's own map?</b></summary>

- **Now:** green menu > `ClusterMap` > `ClusterMapOptions` > **Cluster map
  OFF** (and ON), then reboot. Or disconnect the phone. Uninstalling puts the
  car's map back for good (#153).
- **On the to-do list:** a switch without the green menu, from the steering
  wheel or the car's menu (#183, #23, discussion #166). The buttons differ
  from car to car, so it comes after the green-menu version.

</details>

<details>
<summary><a id="cockpit-views"></a><b>The map isn't centred in another cockpit view (sport, large dials)</b></summary>

Android Auto is never told which view the cockpit is showing, so it draws
the same picture in every view, laid out for one set of insets (#192,
#198). Since v1.2.13 you can give each view its own insets
(`GAL_SECONDARY_LARGE_INSETS`, `GAL_SECONDARY_SPORT_INSETS`, opt-in) and
pick the view from the green menu (`ClusterMapSupport` > 7, 8 or 9): see
[Settings](Settings.md#2-android-auto-map-size-and-position). Following the
cockpit's own view button is being worked on (#183, #205).

</details>

<details>
<summary><a id="smoothness"></a><b>Why is it less smooth than the centre screen?</b></summary>

The picture is decoded in software at up to 30 pictures a second, 800×480,
on a processor that is busy with everything else. The hardware decoder (see
*What do 720p, 1080p and the hardware decoder do?*) takes most of that load
off where it works.

</details>

<details>
<summary><a id="turn-arrows"></a><b>Can I have turn arrows, arrival time and lanes in the dials?</b></summary>

The car's own guidance screens are not fed by the map. With
`CLUSTERMAP_TURN_INFO=1`, VW, SEAT and Skoda get Android Auto's arrow,
distance and road name, on the trains where that jar is known to fit
(`update_result.txt` says whether it was added). On a car with a factory
head-up display the arrow shows there too (discussion #197). Audi has no
such jar yet. Showing the arrows and the map together works on SEAT
with `CLUSTERMAP_KEEP_ARROWS=1`; on VW leave it at 0, because the map has
gone blank when a route starts there (#44 is the exception).

- **Arrival time, remaining distance, lanes** in the car's own guidance:
  Android Auto sends one manoeuvre at a time, and the car's guidance would
  need a jar built per firmware. Not planned now (#119).
- **What the left dial shows** is chosen by the cockpit's own menu (for
  example driving data or the distance to the car ahead), not by this
  project (#45, #44).
- **CarPlay arrows on the cockpit or the head-up display:** on the to-do
  list (#179); Android Auto arrows on the Audi head-up display too (#215).
- **Roundabouts with Waze:** Waze sends the exit number but no exit angle,
  and the arrow was a U-turn at every roundabout (#216). Since v1.2.14 the
  arrow is drawn from the exit number: the exits are spread round the
  roundabout and the arrow takes the one Waze says, so counting the exits on
  the arrow gives Waze's number. The real roundabout's shape may differ.
  Google Maps sends the angle, so its arrows are exact.

</details>

<details>
<summary><a id="music-info"></a><b>Can the cockpit show the song playing?</b></summary>

Yes, on the cockpit's own media page (not on the map):

- **VW, SEAT and Skoda:** set `CLUSTERMAP_MUSIC_INFO=1`, install again and
  reboot (title, artist, cover with Android Auto; title, artist and album
  with CarPlay). `update_result.txt` says whether it was added on your train.
- **Audi:** with CarPlay the cockpit already shows the track from the car
  itself. Android Auto track info on the Audi cockpit is on the to-do list
  (#182); the A3 8V `P5089` has it as an opt-in (`CLUSTERMAP_AU37X_COVER=1`,
  #195).
- **CarPlay cover art** doesn't reach the cockpit on any car so far: the
  car's CarPlay service passes on title, artist and album only (#19, #162).

</details>

<details>
<summary><a id="rear-camera"></a><b>Can the rear camera or drive modes show in the cockpit?</b></summary>

Not with this project. The rear camera goes straight from the camera input
onto the centre screen as a hardware video layer, so there is no picture for
the cockpit to show; it would need a separate native program that takes the
camera input itself (#147). Drive modes are the car's own data, not a
picture. Not planned.

</details>

## CarPlay

<details>
<summary><a id="carplay-cars"></a><b>Which cars have the CarPlay map?</b></summary>

With the iPhone on a cable: a Golf R and a Passat B8 (`P4512`, #67), a SEAT
(`P4709`), a Golf (`K4525`), a Tiguan (`P4521`), an Audi A7 C7.5 (`K3663`,
three cars, #68), A6 C7.5s (`K3663_1`, #147; and through an Ottocast
adapter, discussion #135), a Skoda Superb (`P4526`, #146), a Golf GTE (`P3657`,
#100), a Golf 7 (`K3332`, #45) and VW Discover Pro 8 in (`K3342` MU1427,
#62, #111; through an Otto Pico too). It can switch back to the car's own
map while driving, under investigation (#19, #43). Details in
[CarPlay](CarPlay.md).

</details>

<details>
<summary><a id="carplay-scale"></a><b>How do I make CarPlay's text and icons smaller, with more map?</b></summary>

In `gal_dualscreen.conf`, then install again and plug the iPhone in again:

- **`CLUSTERMAP_CARPLAY_SCALE=130`** (70 to 200): the one to use. The iPhone
  is told the cockpit is a denser display, so it draws smaller text, icons
  and cards and shows more map. The picture stays the same size, so it costs
  no frame rate. Try 130, then 150 or 160.
- `CLUSTERMAP_CARPLAY_FRAME_SCALE`: the older way. The iPhone draws a larger
  picture that the player shrinks, which costs frame rate.
- `CLUSTERMAP_CARPLAY_ZOOM`: a trial that sends iOS a zoom factor; not
  car-tested with this project.

`GAL_SECONDARY_DPI` is for Android Auto only and does nothing for CarPlay.

</details>

<details>
<summary><a id="forget-car"></a><b>The iPhone needs to forget the car?</b></summary>

Yes, once after installing: **Forget This Car** in the iPhone's CarPlay
settings, then plug it in again, so it learns about the cockpit display.

</details>

## The project

<details>
<summary><a id="state"></a><b>What state is the project in?</b></summary>

Experimental, but in daily use on many cars. It was developed on a VW Golf
7.5 (`P4521`). The Android Auto map runs at about 30 pictures a second, with
and without a route, and comes back by itself after the phone is unplugged
and plugged in again.

| Part | State |
|---|---|
| Android Auto map, installer and uninstaller | Tested on many cars (see *Is my car supported?*) |
| Software update and green menu routes | Tested on cars (Golf `P4521`, Golf R `P4512`) |
| Autorun install without the service menu (`Swdlautorun.txt`, on by default) | Tested on a car (Golf `P4521`); Audi untested |
| Hardware video decoding | On by default on `P4521`, `K4525` and, with 1080p, the Audi A3 8V `P5089` (#125, #192) |
| CarPlay map | Working on the cars listed under CarPlay; layout between the dials still being tuned |
| Long drives, reverse camera, waking from sleep | Road-tested on `K4525`; otherwise little testing |

The turn pictograms need `GAL_DUALSCREEN_AAP_MINOR` at 5 or lower, the
shipped value (#4); the hook translates the newer navigation messages, so 6
and 7 should work too, still to be tested on a car.

</details>

<details>
<summary><a id="free"></a><b>Is it free? Someone charged me to install it.</b></summary>

It is free and open source (GPL-3), always. Nobody involved sells it or
charges to install it; if you paid, you paid for free work. The real releases
are only on the [Releases page](https://github.com/MacsInSpace/mib-cluster-map/releases).
Donations are welcome and never expected.

</details>

<details>
<summary><a id="help"></a><b>How can I help?</b></summary>

Car tests with logs and photos are what move the project. Even more: work on
the code directly. Port your own firmware in a fork, fix what you find, and
send a pull request. The [Contributing guide](../CONTRIBUTING.md) explains
how, including a step-by-step for porting your own car. The project is run
by one person with a day job, so replies come a few times a week.

</details>

## Language note

<a id="language"></a>

*The same note is pinned as issue [#36](https://github.com/MacsInSpace/mib-cluster-map/issues/36).*

**Write in your own language if that is easier. It is welcome here, and it costs you nothing.**

I read and translate every issue and comment with an AI assistant (Claude), and I write my replies with it too. So a question in Polish, Russian, Spanish, Italian, German, Hungarian, Czech, Slovak, Romanian, Portuguese, French, Dutch, Turkish, Estonian or Latvian is no harder for me to answer than one in English. I will reply in English — sometimes in both — and you are welcome to keep writing in your own language.

**Logs, photos and `update_result.txt` need no translation at all.** They are the most useful thing you can post, whatever language you speak. Most of what has been fixed in this project was found in a log file, not in a sentence.

**One request.** Please don't ask anyone here to switch to English. A rough description in someone's own words is worth far more to this project than a polite silence, and several cars now working were debugged with people writing in their own language.

<details>
<summary>Polski</summary>

**Pisz w swoim języku, jeśli tak ci łatwiej.** Czytam i tłumaczę wszystkie wpisy za pomocą AI (Claude), więc polski nie jest tu żadnym problemem. Ja odpowiem po angielsku, ty możesz dalej pisać po polsku.

Logi, zdjęcia i plik `update_result.txt` nie wymagają żadnego tłumaczenia — to najbardziej przydatna rzecz, jaką możesz załączyć.

Prośba: nie proś nikogo o przejście na angielski. Opis własnymi słowami, choćby przybliżony, jest dla tego projektu cenniejszy niż uprzejme milczenie.

</details>

<details>
<summary>Русский</summary>

**Пишите на своём языке, если вам так удобнее.** Я читаю и перевожу все сообщения с помощью ИИ (Claude), так что русский здесь не проблема. Отвечать я буду по-английски, а вы можете писать по-русски.

Логи, фотографии и файл `update_result.txt` переводить не нужно вообще — это самое полезное, что можно приложить.

Просьба: не просите никого переходить на английский. Описание своими словами, пусть и приблизительное, полезнее для проекта, чем вежливое молчание.

</details>

<details>
<summary>Español</summary>

**Escribe en tu idioma si te resulta más cómodo.** Leo y traduzco todos los mensajes con una IA (Claude), así que el español no supone ningún problema. Yo responderé en inglés y tú puedes seguir escribiendo en español.

Los registros, las fotos y el archivo `update_result.txt` no necesitan traducción — son lo más útil que puedes adjuntar.

Una petición: no pidas a nadie que cambie al inglés. Una descripción con tus propias palabras, aunque sea aproximada, vale más para este proyecto que un silencio cortés.

</details>

<details>
<summary>Italiano</summary>

**Scrivi nella tua lingua, se ti è più comodo.** Leggo e traduco tutti i messaggi con un'IA (Claude), quindi l'italiano non è un problema. Io risponderò in inglese e tu puoi continuare a scrivere in italiano.

Log, foto e il file `update_result.txt` non hanno bisogno di traduzione — sono la cosa più utile che puoi allegare.

Una richiesta: non chiedere a nessuno di passare all'inglese. Una descrizione con parole proprie, anche approssimativa, vale più per questo progetto di un silenzio cortese.

</details>

<details>
<summary>Deutsch</summary>

**Schreib in deiner eigenen Sprache, wenn dir das leichter fällt.** Ich lese und übersetze alle Beiträge mit einer KI (Claude), Deutsch ist hier also kein Problem. Ich antworte auf Englisch, du kannst weiter auf Deutsch schreiben.

Logs, Fotos und die Datei `update_result.txt` müssen überhaupt nicht übersetzt werden — sie sind das Nützlichste, was du anhängen kannst.

Eine Bitte: Fordere hier niemanden auf, auf Englisch zu wechseln. Eine grobe Beschreibung in eigenen Worten ist für dieses Projekt wertvoller als höfliches Schweigen.

</details>

<details>
<summary>Magyar</summary>

**Írj a saját nyelveden, ha az kényelmesebb.** Minden hozzászólást MI (Claude) segítségével olvasok és fordítok, úgyhogy a magyar itt nem probléma. Én angolul válaszolok, te továbbra is írhatsz magyarul.

A naplófájlokat, a fényképeket és az `update_result.txt` fájlt egyáltalán nem kell lefordítani — ezek a leghasznosabbak, amiket csatolhatsz.

Egy kérés: ne kérj senkit arra, hogy váltson angolra. A saját szavakkal írt, akár pontatlan leírás többet ér ennek a projektnek, mint az udvarias hallgatás.

</details>

<details>
<summary>Čeština / Slovenčina</summary>

**Piš svým jazykem, pokud je to pro tebe snazší.** Všechny příspěvky čtu a překládám pomocí AI (Claude), takže čeština ani slovenština tu nejsou žádný problém. Odpovídat budu anglicky, ty můžeš dál psát svým jazykem.

Logy, fotografie a soubor `update_result.txt` není potřeba překládat — jsou to nejužitečnější věci, které můžeš přiložit.

Prosba: nežádej nikoho, aby přešel na angličtinu. Popis vlastními slovy, i přibližný, má pro tento projekt větší cenu než zdvořilé mlčení.

</details>

<details>
<summary>Română</summary>

**Scrie în limba ta, dacă îți este mai comod.** Citesc și traduc toate mesajele cu ajutorul unei IA (Claude), așa că româna nu este nicio problemă. Eu voi răspunde în engleză, tu poți scrie în continuare în română.

Jurnalele, fotografiile și fișierul `update_result.txt` nu au nevoie de traducere — sunt cele mai utile lucruri pe care le poți atașa.

O rugăminte: nu cere nimănui să treacă la engleză. O descriere în propriile cuvinte, chiar și aproximativă, valorează mai mult pentru acest proiect decât o tăcere politicoasă.

</details>

Any language not listed is fine too — write it anyway.
