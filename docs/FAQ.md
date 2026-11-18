# Frequently asked questions

Click a question to open it. Not answered here? Ask in
[Discussions > Q&A](https://github.com/MacsInSpace/mib-cluster-map/discussions/categories/q-a), or open an
[issue](https://github.com/MacsInSpace/mib-cluster-map/issues) with your logs if something is broken.

- [Your car](#your-car)
- [Installing and updating](#installing-and-updating)
- [When something is wrong](#when-something-is-wrong)
- [What it can and cannot do](#what-it-can-and-cannot-do)
- [CarPlay](#carplay)
- [The project](#the-project)

## Your car

<details>
<summary><b>Is my car supported?</b></summary>

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
| Audi MIB2 High, Harman/Tegra | `MHI2_ER_AU`, `MHI2_US_AU` | A4 B9 / Q5 FY `K3346`, A3/S3 8V `P5089`, `P5153`, `P4203`, A6/A7 C7.5 `K3663`, US A7 `K3341` | A6/A7 C7.5 `K3663` |
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
- **`P4512`**: Golf R; Passat B8 (#47). `P4512_2` music info works (#24),
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
  - Wired CarPlay works (#62, #111; without a trial line since v1.2.6), and
    #118 reports everything working. CarPlay through an Otto Pico wireless
    adapter works too (#111).
  - Turn and music info are not available on `K3342`: its interface differs
    from the one those jars were built for.
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
  v1.2.4) work. An RS3 is still to be tried.
- **A7 C7.5 `AU57x_K3663`**: Android Auto and CarPlay on the cockpit
  (context 73, set by the installer; its CarPlay library is accepted without
  a trial line since v1.2.1). With the Audi NavActiveIgnore, which the
  installer adds (M.I.B.'s build; the toolbox's VW build does not fit this
  unit), a CarPlay route (Waze) stays on the cockpit. The steering-wheel
  roller zooms the CarPlay map ([CarPlay](CarPlay.md#steering-wheel-zoom-audi-a6a7-c75)).
- **A6 C7.5** has the same firmware and works too (#68; a 2016 facelift out
  of the box on v1.2.1; #114 and another A7 `K3663_1`, #140, on v1.2.6; an
  A6 Avant C7.5 `K3663_1` with CarPlay too, #147; a 2015 A6 `K3663_1`
  with CarPlay through an Ottocast wireless adapter, discussion #135).
- **US A7 C7.5 `MHI2_US_AU57x_K3341`** works with Android Auto (same window
  and context; the map stays on a route with the Audi NavActiveIgnore, which
  the installer adds; CarPlay not tried).
- **Pre-facelift A6 C7 `AU57x_P3236`**: not supported yet; a trial line from
  its files is being tried (#127, #122).
- **A6 C7 `AU57x_P3634`**: not supported, but its owner updated the unit to
  `K3663_1` and everything works there (#142); the same may suit `P3236`.

</details>

<details>
<summary>VW Discover Pro, Japan, <code>MHI2_JP_VW48x_</code></summary>

- **`P0953`**: trial. It has the same Android Auto program as `P4708` and
  needs no trial line (#37); being tested.

</details>

</details>

<details>
<summary><b>How do I find my firmware train?</b></summary>

After installing, the green menu **Status** screen shows it (hold MENU >
`Testmode` > `Green Developer Menu` > `ClusterMap`). It is also the first
thing in `ClusterMap/update_result.txt` after any install attempt, even one
that installed nothing. "Software: 1367" under `Setup` > `System information`
is a hint, not proof: two cars with the same number can have different
trains.

</details>

<details>
<summary><b>My car is not listed, or says "wanted". Can you support it?</b></summary>

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
<summary><b>My firmware is older. Should I update it first?</b></summary>

Sometimes that is the shortest way:

- **VWG11 `S2125`**: update the unit to `MHI2_ER_VWG11_K3342` (MU1427)
  through a VW dealer or a firmware package you trust (owners have used
  `MHI2_ER_VWG11_K3342_1_AIO_MU1427`), check the train and MU in the green
  menu afterwards, then install. If you already had NavActiveIgnore from
  M.I.B., use the stock `gal.json` (#28).
- **Audi A6 C7 `P3634`**: an owner updated to `K3663_1`, which is supported,
  and everything worked (#142). The same may suit `P3236`.

Updating firmware is at your own risk; this project does not host or link
firmware.

</details>

## Installing and updating

<details>
<summary><b>How do I update to a new version?</b></summary>

Install it over the old one; there is no need to uninstall first. Replace the
files on the SD card with the new release (the `ClusterMap` folder,
`Custom`, `metainfo2.txt`, `Swdlautorun.txt`), run the update as the first
time, then reboot. The lines you changed in `gal_dualscreen.conf` last time
are remembered and put back; set `CLUSTERMAP_KEEP_SETTINGS=0` for a clean
install.

</details>

<details>
<summary><b>Where do I change a setting?</b></summary>

Two places:

- **The green menu** (hold MENU > `Testmode` > `Green Developer Menu` >
  `ClusterMap`) has switches for the common ones: sharper map, light/dark,
  hardware decoder, keep the phone's map, cluster map off. A switch changes
  the unit directly and is kept by the next install.
- **Everything else** is a line in `ClusterMap/gal_dualscreen.conf` on the SD
  card. Remove the `#` at the very start of the line, change the value, save,
  and **install again** (then reboot). Editing the file alone changes
  nothing on the unit.

Every setting is listed in the [Install guide](Install.md#settings).

</details>

<details>
<summary><b>Do I need to change the map size or insets?</b></summary>

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
<summary><b>What do 720p, 1080p and the hardware decoder do?</b></summary>

By default Android Auto sends 800×480, decoded in software at up to 30
pictures a second.

- **Hardware decoder** (`GAL_PLAYER_DECODER=hw`, or **Hardware decoder ON**
  in `ClusterMapOptions`): the same picture at about a third of the
  processor time. On by default on `P4521`, and on `K4525` from the next
  release. Elsewhere, run **Hardware decoder check** in `ClusterMapSupport`
  first and report what it says.
- **`CLUSTERMAP_720P=1` / `CLUSTERMAP_1080P=1`**: test settings that ask for
  a 1280×720 or 1920×1080 stream, cropped to the cockpit window. Only worth
  it on the larger 1440×455 Audi cockpits; a 1010×376 cockpit gains nothing
  from 1080p. The DPI and insets stay the 800×480 ones for now, so set your
  own. The car-tested Audi 1080p example is in the
  [Install guide](Install.md#settings-owners-have-settled-on).

</details>

<details>
<summary><b>How do I uninstall?</b></summary>

Green menu > `ClusterMap` > **Uninstall and restore original state**, then
reboot. Without the menu: on a computer, move `UNINSTALL.txt` from the folder
`to uninstall, move this file up one folder` up into `ClusterMap`, and run
the same update again. What it restores is in the
[Install guide](Install.md#what-the-installer-changes).

</details>

## When something is wrong

<details>
<summary><b>The map shows, then goes when a route starts</b></summary>

The car's navigation takes the cockpit back as soon as the phone starts a
route, unless **NavActiveIgnore** is loaded. The installer adds it on the
trains where it is known to work. On others, `update_result.txt` says it is
not loaded: put `CLUSTERMAP_ADD_NAVIGNORE=1` in `gal_dualscreen.conf` and
install again. On VW Discover Pro 8 in with an iPhone, leave it off (see
*Is my car supported?* > VW 8 in).

</details>

<details>
<summary><b>The cockpit says "loading", or the car's own map keeps coming back</b></summary>

Every car that showed this (#105, #24) also had an older cluster renderer
from another project installed (VcMOSTRenderMqb, `/navigation/opengl-render-qnx`),
which takes the same window. v1.2.7 switches it off at install. Install
v1.2.7 or later and reboot.

</details>

<details>
<summary><b>It doesn't work. How do I send logs?</b></summary>

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
<summary><b>It stopped working with a wireless adapter</b></summary>

A cable always gives the most. Many wireless CarPlay adapters never ask the
car for the cockpit picture ([CarPlay](CarPlay.md#wireless-adapters)). Some
Android Auto adapters stop working when the car offers a second display: with
a SmartBox-D824 the centre screen stayed black (#101). What fixed it there:
in Android Auto's developer settings on the phone, allow only the 800x480
video resolution. Otherwise use a cable, or switch the cockpit map off (green
menu, `ClusterMapOptions` > **Cluster map OFF**) to have Android Auto as
before. AAWireless (including TWO), a Motorola MA1 and, for CarPlay, an Otto
Pico are reported working.

</details>

## What it can and cannot do

The cockpit shows the picture the phone makes for a second display. The car
side only offers that display and plays what arrives: it draws nothing of its
own and cannot change what an app sends.

<details>
<summary><b>Which apps show a map?</b></summary>

Each app decides whether it draws on the cockpit. Google Maps, Waze and
Yandex do. Yanosik, TomTom and Mapy.com send only their icon, and opening one
of them on the centre screen replaces the map on the cockpit with that icon
(#120, #123, #107). Only the app's makers can change that.

</details>

<details>
<summary><b>Can I change what is on the map, or its colours?</b></summary>

- **Content**: alerts, speed limits, the turn card and the arrival card are
  the app's. Waze shows no alerts on the cockpit (#128). You can change the
  size (`GAL_SECONDARY_DPI`) and the area the app keeps clear
  (`GAL_SECONDARY_INSETS`), not the content. At a high DPI Google Maps drops
  its arrival card.
- **Day and night**: Google Maps follows the car. Waze stays dark on the
  cockpit whatever the centre screen shows (#129, #40). The green menu can
  force light or dark (`ClusterMapPicture`).
- **The car's own overlays**: lines the cockpit draws over its map, such as
  the street name bar on an Audi A6/A7, stay there (#126). Raise the bottom
  inset so the app keeps that strip clear.

</details>

<details>
<summary><b>Can I zoom the cockpit map?</b></summary>

Not with Android Auto: it has no zoom for the cockpit map, and the
steering-wheel roller only changes the car's own hidden map
([why](Development.md#zoom)). With CarPlay the roller zooms on the Audi A6/A7
C7.5. Switching between the phone's map and the car's map from the steering
wheel is not possible so far.

</details>

<details>
<summary><b>Why is it less smooth than the centre screen?</b></summary>

The picture is decoded in software at up to 30 pictures a second, 800×480,
on a processor that is busy with everything else. The hardware decoder (see
*What do 720p, 1080p and the hardware decoder do?*) takes most of that load
off where it works.

</details>

<details>
<summary><b>Can I have turn arrows, arrival time and lanes in the dials?</b></summary>

The car's own guidance screens are not fed by the map. With
`CLUSTERMAP_TURN_INFO=1`, VW, SEAT and Skoda get the arrow, distance and road
name, on the trains where that jar is known to fit (not on `K3342`). Audi
has no such jar yet. Showing the arrows and the map together works on SEAT
with `CLUSTERMAP_KEEP_ARROWS=1`; on VW leave it at 0, because the map has
gone blank when a route starts there (#44 is the exception).

</details>

<details>
<summary><b>Can the rear camera or drive modes show in the cockpit?</b></summary>

Not with this project. The rear camera goes straight from the camera input
onto the centre screen as a hardware video layer, so there is no picture for
the cockpit to show; it would need a separate native program that takes the
camera input itself (#147). Drive modes are the car's own data, not a
picture. Not planned.

</details>

## CarPlay

<details>
<summary><b>Which cars have the CarPlay map?</b></summary>

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
<summary><b>How do I make CarPlay's text and icons smaller, with more map?</b></summary>

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
<summary><b>The iPhone needs to forget the car?</b></summary>

Yes, once after installing: **Forget This Car** in the iPhone's CarPlay
settings, then plug it in again, so it learns about the cockpit display.

</details>

## The project

<details>
<summary><b>What state is the project in?</b></summary>

Experimental, but in daily use on many cars. It was developed on a VW Golf
7.5 (`P4521`). The Android Auto map runs at about 30 pictures a second, with
and without a route, and comes back by itself after the phone is unplugged
and plugged in again.

| Part | State |
|---|---|
| Android Auto map, installer and uninstaller | Tested on many cars (see *Is my car supported?*) |
| Software update and green menu routes | Tested on cars (Golf `P4521`, Golf R `P4512`) |
| Autorun install without the service menu (`Swdlautorun.txt`, on by default) | Tested on a car (Golf `P4521`); Audi untested |
| Hardware video decoding | On by default on `P4521`, and on `K4525` from the next release; Audi A3 8V 1080p car-tested (#125) |
| CarPlay map | Working on the cars listed under CarPlay; layout between the dials still being tuned |
| Long drives, reverse camera, waking from sleep | Road-tested on `K4525`; otherwise little testing |

The turn pictograms need `GAL_DUALSCREEN_AAP_MINOR` at 5 or lower, the
shipped value (#4); the hook translates the newer navigation messages, so 6
and 7 should work too, still to be tested on a car.

</details>

<details>
<summary><b>Which language should I write in?</b></summary>

Yours. Issues and comments in any language are welcome, and several cars now
working were debugged with people writing in their own. Logs and photos need
no translation at all. The same in nine languages:
[#36](https://github.com/MacsInSpace/mib-cluster-map/issues/36).

</details>

<details>
<summary><b>How can I help?</b></summary>

Car tests with logs and photos are what move the project. Even more: work on
the code directly. Port your own firmware in a fork, fix what you find, and
send a pull request. The [Contributing guide](../CONTRIBUTING.md) explains
how, including a step-by-step for porting your own car. The project is run
by one person with a day job, so replies come a few times a week.

</details>
