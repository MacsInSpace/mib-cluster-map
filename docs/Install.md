# Install guide

Three ways in, all running the same installer. Use the first unless you
already work in the toolbox or over SSH.

| Route | Needs | Tested on a car |
|---|---|---|
| 1. Software update from the SD card | Nothing | Pending |
| 2. Green menu screen | The ClusterMap screen, which route 1 adds, or the [MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) | Pending |
| 3. SSH | The toolbox's SSH service | Yes |

Before you start: park, keep the engine running or a charger connected, and
never switch the ignition off while something is installing. Hours of
ignition-on testing flattened a healthy battery during development. If a
screen does not look like the description, stop and ask in an issue.

**Recommended in any case:** install the toolbox's SSH service
(`Customization` > `Advanced` > **Install SSHD service**,
[guide](https://github.com/jilleb/mib2-toolbox/wiki/SSH-Login)). It is the
way back into the unit if the centre screen ever fails to start.

## The SD card

1. Format a 2 to 32 GB card as FAT32. This erases it.
   - Windows: right-click the card > `Format` > `FAT32`.
   - macOS: Disk Utility > the card's device > `Erase` > `MS-DOS (FAT)`,
     scheme `Master Boot Record`.
2. Copy everything inside the release zip to the card:

   ```text
   (SD card)
   ├── ClusterMap/      installer, programs, settings
   ├── Custom/          the menu screen, for route 2 via the toolbox
   ├── metainfo2.txt    makes the card a software update
   └── Swdlautorun.txt  starts the update by itself when the card goes in (below)
   ```
3. Put it in **SD slot 1**, with slot 2 empty. Slot 2 or a USB stick also
   works for route 1: since v1.2.5 the green menu's entries follow the card
   the update ran from (after the reboot). Keep the card in that place to use
   the menu. Route 2 needs slot 1.

## Route 1: software update

1. Hold **MENU** until the service screen appears (several seconds).
2. `Software updates/versions` > `Update` (top right) > the SD card >
   **`MIB Cluster Map`**.
3. Let it run. The unit may restart, then show a list of modules mostly marked
   `N/A` and `ClusterMap` `OK`: press back (top right). A screen headed
   **Version back documentation** ("Start diagnostic tester ... Accepting the
   error code leads to a restart") is normal: press `Cancel`. The unit
   restarts once more.
4. Back at the home screen, hold the power button for ten seconds to reboot.

**Autorun (on by default):** `Swdlautorun.txt`, at the top of the card, makes
units that honour it start this update by themselves when the card goes in
(the trigger M.I.B. uses; a Golf started it straight away, Audi untested).
The update renames the file to `_Swdlautorun.txt` when it finishes, so it
does not start again after the restart; installing on a second car means
renaming it back first. If nothing happens within two minutes, the unit does
not honour it: use the menu above. To keep the card from ever starting on
its own, rename the file to `_Swdlautorun.txt` before inserting it.

What it does, without asking:

- copies the ClusterMap screen to the green menu and switches that menu on;
- checks the firmware and installs **the map** where there is a profile for
  it, otherwise **the turn arrows** where that jar is known to work, otherwise
  **nothing**, and then collects the files needed to add the unit (see
  [Getting your unit added](#getting-your-unit-added));
- with the map: adds the NavActiveIgnore patch if it is missing, and switches
  off the turn-arrows jar if it is loaded (the two cannot run together);
- keeps every original file it changes, on the unit and on the card.

Its report is `ClusterMap/update_result.txt` on the card. A good run ends with
`CLUSTERMAP_INSTALL_OK` (map) or `CLUSTERMAP_TURN_BY_TURN_OK` (arrows).

Two marker files change what the update does. Each ships in a folder whose
name says what to do with it; move the file up into `ClusterMap` itself, run
the update, then move it back:

| Marker | Folder | The update then |
|---|---|---|
| `UNINSTALL.txt` | `to uninstall, move this file up one folder` | removes everything and restores the original state |
| `COLLECT.txt` | `to only check compatibility, move this file up one folder` | installs nothing: writes the status check to `update_result.txt` and collects the porting files. Only the menu screen file is copied to the unit |

## Route 2: green menu

If route 1 has run, the screen is already there. Otherwise add it with the
toolbox: its files and ours on the same card (merge the `Custom` folders and
**keep the toolbox's `metainfo2.txt`**), then green menu > `mqbcoding` >
`Customization` > `GreenMenu` > **Install GreenMenu screens and scripts from
Custom/GreenMenu**. A message about a missing `scripts` folder is harmless.
Leave the green menu and open it again.

Open it with MENU (hold) > `Testmode` > `Green Developer Menu` >
**`ClusterMap`**:

The green menu only opens once developer mode is switched on in the unit's
coding (address 5F, with VCDS, OBDeleven or the like).
On some Audis it opens another way: on an A3 8V, go into the Settings menu
first, then hold both steering-wheel paddles (nav and radio) up for 5 s (#157).
Neither route 1 nor uninstalling needs the green menu: route 1 installs from
the card, and the `UNINSTALL` marker on the card removes everything.

| Entry | What it does |
|---|---|
| 1. Status and compatibility check | Firmware train, verdict, what is installed, Java patches |
| 2. Install cluster map | The same installer as route 1 |
| 3. Save logs to SD | For a problem report. Before rebooting: logs are in RAM |
| 4. Uninstall and restore original state | Full revert |
| ClusterMapPicture > 1, 2. Sharper map ON / OFF | `CLUSTERMAP_FULL_FRAME` without editing the card. Reboot after |
| ClusterMapPicture > 3, 4. Sharpest map, 720p / 1080p | `CLUSTERMAP_720P` / `CLUSTERMAP_1080P`: the cockpit window's own pixels 1:1. Only on a window larger than 800×480; 1080p needs the hardware decoder. Sharper map ON or OFF goes back. Reboot after |
| ClusterMapPicture > 5, 6, 7. Map always light / always dark / follows the headlights | `GAL_SECONDARY_UI_THEME`. Google Maps; Waze stays dark. Reboot after |
| ClusterMapOptions > 1, 2. Hardware decoder ON / OFF | `GAL_PLAYER_DECODER`. From the next phone connection |
| ClusterMapOptions > 3, 4. Keep the phone's map ON / OFF | `GAL_PLAYER_REASSERT`, for "phone map for a moment, then the car's map". From the next phone connection |
| ClusterMapOptions > 5, 6. Cluster map OFF / ON | `GAL_DUALSCREEN_ENABLE`, for a wireless adapter that stops working with the map. Nothing is removed. Reboot after |
| ClusterMapSupport > 1. Collect files for porting (quick) | About 2.5 MB, read only |
| ClusterMapSupport > 2. Collect for porting, with Java image (55 MB, slow) | Only for a turn-arrows port |
| ClusterMapSupport > 3. Switch to turn-by-turn arrows instead (no map) | Removes the map, installs the arrows. Install switches back |
| ClusterMapSupport > 4. Hardware decoder check | Decodes a one-second test clip with the unit's own decoder and compares every picture with the reference. Says `usable` or `not usable`; changes nothing |
| ClusterMapSupport > 5, 6. Performance figures in the log ON / OFF | `GAL_PLAYER_STATS`, when a report is about speed |

A switch changes the unit's copy of the settings, and the next install from a
card keeps the choice unless the card's `gal_dualscreen.conf` sets that line
itself. Settings that add or remove files on the unit (turn info, music info,
NavActiveIgnore, the CarPlay map) are not in the menu: change them on the card
and install.

The status check says `supported: yes (tested firmware)`, `yes (UNTESTED
firmware ...)` (it may work; please report the result) or `NO` (stop; nothing
was changed). Run Install, wait for `CLUSTERMAP_INSTALL_OK`, leave the menu
and reboot. Do not change entries this guide does not mention.

## Route 3: SSH

SD card in slot 1, laptop on the car's wifi hotspot, SSH in as root:

```sh
mount -uw /fs/sda0
sh /fs/sda0/ClusterMap/GEM/install.sh       # or ClusterMap/enable_hook.sh for the map alone
sh /fs/sda0/ClusterMap/GEM/uninstall.sh     # to remove
```

Then reboot. `enable_hook.sh --help` lists its options.

## Use it

Wait about two minutes after the unit starts. Plug in the phone, start a map
on it, and put the cluster in **map view** with the steering wheel buttons.
The phone's map appears within a few seconds and stays when a route starts.
The car's own navigation still works; the cluster shows the phone's map only
while the phone sends it.

## What the installer changes

| Where | What |
|---|---|
| `/mnt/system/etc/eso/production/smartphone_integrator.json` | adds the hook to the Android Auto program's start-up, and the CarPlay hook to CarPlay's where the unit's CarPlay library fits; original kept as `.gal-dualscreen.original` and in `ClusterMap/backups/` on the card |
| `/mnt/app/eso/lib/gal_dualscreen/` | the hooks, a helper library, the CarPlay supervisor script, a copy of the settings |
| `/mnt/app/navigation/stream-player` | the video player |
| `/mnt/app/eso/hmi/lsd/lsd.sh` | Java patch lines: NavActiveIgnore added if missing (on the trains above, or anywhere with `CLUSTERMAP_ADD_NAVIGNORE=1`), the turn-arrows jar's line removed (map) or added (arrows). Previous file kept as `lsd.sh.before_<jar>` |
| `/mnt/app/eso/hmi/engdefs/cluster-map.esd` | the menu screen |
| `/mnt/system/etc/pf*.conf` | CarPlay map only: one firewall rule letting the iPhone's cluster video (TCP 6031) in on its USB CarPlay link, marked `# clustermap carplay map`; originals kept as `.clustermap.original` |
| `/mnt/app/root/mibr-carplay111-safearea.conf` | CarPlay map only: the part of the window clear of the dials, from `GAL_SECONDARY_INSETS` |

Uninstall puts all of it back and removes the menu screen. Three things stay,
all harmless: the engineering menu stays switched on, the unused backup copies
of the files it edited stay beside them, and any fault the SD update logged
stays (see [Fault B201A00](#fault-b201a00)). Run the status check before the
reboot: it should say the hook is not installed. To use the green menu again
later, run the update with `COLLECT.txt`.

### Fault B201A00

Any software update run from SD can log `B201A00 Check Software Version
Management` in the head unit (5F), even when this package then installs
nothing. One owner's scan shows it, with a sporadic `U10CF00`, at the minute of
the SD update and before anything of this project ran (#10). Uninstalling does
not clear it. It is the head unit reporting a software change; a workshop can
clear it with a diagnostic tool's installation-change confirmation. Whether it
has any other effect is not known.

One owner cleared it themselves in 5F with the adaptation "Confirmation of
installation change", using a key from a third-party tool (#10). We have not
tried that route.

If the update stops on another module, for example "device not responding"
naming the instrument cluster, pressing Skip let the install finish on one car
(#40).

## Cluster map window

The cluster only shows the head unit's map window at that window's own size:
800×480 on the Golf, 1010×376 on some SEAT and Skoda clusters. A window of
another size arrives as coloured stripes. The installer reads the size from
the display manager (`dmdt gd`, window 33) and opens the player's window at
it. Android Auto normally uses 800×480, so where the window has another shape
the phone is asked to leave margins (0×182 for 1010×376) and the player scales
the rest to fill the window. Optional `CLUSTERMAP_720P=1` and
`CLUSTERMAP_1080P=1` test modes request 1280×720 or 1920×1080 with margins
leaving the cockpit window's pixels; the player crops them and displays them
1:1 when dimensions match. The phone/unit may reject the resolution if the
primary sink does not advertise an HD entry. CarPlay is asked for the
window's size. If the size cannot be read, the card's `GAL_PLAYER_WINDOW`
is used when set (for example `GAL_PLAYER_WINDOW=1010x376`), then the size
the player found on this cockpit at an earlier start, otherwise the
usual size for the make (1010×376 on SEAT and Skoda, 800×480 on VW and
anything else). The install
output and the unit's copy of the settings (`GAL_PLAYER_WINDOW`,
`GAL_SECONDARY_MARGINS`) show what was chosen.

The display manager only lists window 33 once the cockpit has shown it, so
the installer can be left with a guess. The player therefore reads the size
again each time it starts. If it differs, it opens the window at the real size
and corrects the two settings for the next start, and saves the size for the
next install. Until then the picture can have black bars. CarPlay's size
only changes on the next install. (Until v1.2.1 that correction never ran:
its script could not find its own folder, #95.)

## Settings

Edit `ClusterMap/gal_dualscreen.conf` on the card, run the install again so
the unit's copy is refreshed, and reboot. The file documents every key.

**A line that starts with `#` is switched off.** Many settings ship that way.
To use one, delete the `#` at the very start of the line, and keep only one
active line per setting:

```ini
#CLUSTERMAP_CARPLAY_CARD_POSITION=left    <- off: no effect, whatever the value
CLUSTERMAP_CARPLAY_CARD_POSITION=top      <- on
```

The same goes for any line you were asked to add, such as `GAL_PROFILE_TRIAL=`:
it must start at the beginning of the line, with no `#` in front.

**Every setting, grouped by what it fixes and with drop-downs, is on the
[Settings](Settings.md) page**, along with why there are settings at all. The
file on the card uses the same sections.

### Settings owners have settled on

The dials differ between cars, so these are starting points rather than
recommendations. All are `GAL_SECONDARY_DPI` with `GAL_SECONDARY_INSETS` as
top, bottom, left, right. With both left at `auto` the installer picks the
SEAT, Skoda, VW or Audi row marked *auto* for you; to try another row, put its
numbers in the file. When owners of a car confirm values on the road, that
row becomes the *auto* one for the car in the next release, so a car left
on `auto` follows it without editing anything.

| Cluster | DPI | Insets | From |
|---|---|---|---|
| SEAT 1010×376 (`P4708`, `P4709`), *auto* | 125 | `105,127,127,127` | SEAT owners, #4 and #19 (140 until beta11; owners found it too large) |
| SEAT, for Waze | 110 | `105,127,127,127` | DaniFR3, #4 |
| VW 12.3 in Passat B8 (`K4525`) | 145 | `56,73,127,127` | d4nt387, #8 |
| VW 12.3 in Tiguan (`K4525`) | 145 | `56,120,127,127` | totocastellano-cmd, #27 |
| VW Tiguan / Tiguan Allspace (`P4521`), 1010×376 cockpit, full frame, *auto* for VW 1010×376 since v1.2.7 | 115 | `102,52,127,127` | brzeskibartosz, #95 (turn card showing; ETA card not yet) |
| Skoda 1010×376 (`P4526`), *auto* | 125 | `40,127,127,127` | raskrivuska, #15 |
| Audi A4 B9 1440×455 (`K3346`), *auto* | 140 | `40,40,127,127` | mariuszhejnold-arch, #14 |
| Audi Q5 FY 1440×455 (`K3346`), *auto* | 140 | `40,40,127,127` | pioottr20, #96 (context 72) |
| Audi Q5 FY, smaller card, car above the bottom bar | 100 | `40,90,127,127` | pioottr20, #96 |
| Audi A3/S3/RS3 8V 1440×455 (`P5089`), 1080p, *auto* since v1.2.12 | 160 | `50,100,75,75` | kashavsehra and getmarch1, #192 (1080p, hardware decoder) |
| Audi A3/S3 8V 1440×455 (`P5089` without 1080p, `P5153`), *auto* | 100 | `60,150,10,10` | kashavsehra, #51 and #78 (tuned with **Sharper map ON**; smaller cards, car centred; context 70) |
| Audi A3/S3 8V, the values before v1.2.0 | 140 | `40,40,127,127` | kashavsehra, #51 |
| Audi A7 C7.5 800×298 (`K3663`), *auto* | 125 | `40,40,127,127` | Seif, by email (context 73) |
| Audi A6 C7.5 facelift (`K3663`), *auto* | 125 | `40,40,127,127` | nkady, #68 (v1.2.1, out of the box) |
| Audi Q2 1440×455 (`P3243`), *auto* since v1.2.12 | 125 | `40,40,127,127` | window from paulandrei2006's logs, #157; values not tuned yet (context 70) |
| VW 12.3 in, ETA card showing (`K4525`) | 138 | `52,82,127,127` | totocastellano-cmd, #20 and #12 (`53,83,127,127` on a second car: the same within a pixel) |
| VW 12.3 in Passat B8 2019 (`K4525`), ETA card showing, with `GAL_SECONDARY_UI_THEME=0` | 138 | `56,73,127,127` | danielszyszko-ui, #41 |
| VW Golf (`P4521`), ETA card showing, Google Maps and Waze, *auto* for VW | 138 | `52,82,127,127` | tvarszegi1, #8, road-tested |
| VW Passat B8 2018 (`P4512_1`), small and large dials, *auto* for VW | 138 | `52,82,127,127` | slechtaadam-byte, #47 |

Car-tested Audi 1080p example (1920×1080 stream, 1440×455 cockpit window):

```ini
CLUSTERMAP_1080P=1
GAL_PLAYER_DECODER=hw
GAL_PLAYER_NVSS_OUTPUT=1
GAL_SECONDARY_DPI=160
GAL_SECONDARY_INSETS=45,85,75,75
```

Since v1.2.12 the A3 8V `P5089` gets this by itself, with insets `50,100,75,75`.

**Insets with Sharper map (full frame) on a 1440×455 Audi:** the first 114 lines top
and bottom count as the old margin band, so a top or bottom inset of 114 or less
comes out as 0 and changing it does nothing (#96). Use a larger value, or
`CLUSTERMAP_FULL_FRAME=0`. The installer says so when it happens.

`GAL_PLAYER_DECODER=hw` with `GAL_PLAYER_NVSS_OUTPUT=1` is Audi-only; Skoda
reports output 1 as `0x0`.

Lower DPI makes the map and its text smaller, so more of the map shows; below
about DPI 140 Google Maps changes from two overlay cards to one in the middle.
Google Maps also drops its arrival-time card when the space left to it is too
short, and DPI is the lever: the one setting anyone has shown with the card
visible on a 12.3 in cluster is 138 with a bottom inset of 82 (#20, #27).
Waze picks its own colours and ignores the day setting.

Logs are kept in RAM only (`/tmp/gal_dualscreen.log`, `/tmp/stream-player.log`)
and lost at reboot. **Save logs to SD** copies them, with the system log, to
a new numbered folder in `ClusterMap/run_logs/` each time. Read them before posting: the system log can contain
phone names and Bluetooth addresses.

## If it does not work

| What you see | What to do |
|---|---|
| The car's own map, or "no map" | Check the cluster is in map view. Unplug the phone, wait ten seconds, plug it in |
| Audi A6/A7 C7.5: the compass, or a blank nav tab, with CarPlay running | The cockpit's nav tab is not in map view. The installer adds `ClusterMapGfxKeep.jar` on `K3663`, which switches it while the CarPlay map is up; check **Status** says `cockpit map view: loaded`, and `/tmp/clustermap-gfxstate.log` in **Save logs**. Elsewhere choose the map in the cockpit's own nav menu |
| CarPlay works on the centre screen through a wireless adapter, but the cockpit keeps the car's map | Try a cable. Many adapters never open the iPhone's second screen, which the cockpit map needs ([CarPlay](CarPlay.md#wireless-adapters)) |
| A wireless adapter connects, then drops every few seconds | In the adapter's own app: automatic standby **off**, VAG crash fix **off** (that fix is for VAG *Technisat* units, not Harman), adapter firmware up to date (#12, #35) |
| The phone keeps disconnecting | Save logs, uninstall, reboot, open an issue |
| The map appears, then goes blank when a route starts, or the cluster says "navigation on mobile device is active" | `NavActiveIgnore` is not loaded. The installer adds it on `P4521`, `K4525`, `P4512`, US `P3662`, Skoda `P4526`, SEAT `P4709`, the Audi A6/A7 C7.5 (`K3663`, `K3341`, `P3236`, `P3237`, `P3327` and any A6/A7 C7.5 train without its own line) and the Q2 `P3243` (the Audi build). On any other firmware set `CLUSTERMAP_ADD_NAVIGNORE=1` and install again, or apply it from the MIB2 Toolbox (**Customization > Navigation > Ignore navigation-active status**). Check SSH works first — see [Safety and recovery](#safety-and-recovery) |
| The map appears, then goes blank when a route starts, with `NavActiveIgnore` loaded | Run the install again: something re-enabled the turn-arrows jar |
| Black cluster with `GAL_PLAYER_DECODER=hw` | `GAL_PLAYER_NVSS_OUTPUT=0`, or back to `sw` |
| The centre screen stays black after a reboot | See below |

## Safety and recovery

What the installer does to avoid a unit that will not start:

- **Wrong firmware is refused** before anything is written, and the hook
  checks again every time Android Auto starts; on a mismatch it does nothing.
- **Only two existing system files are edited**: the smartphone start-up
  configuration and the Java start-up script. Each new version is written to
  a separate file, checked, and only then moved into place. The configuration
  is validated with the unit's own JSON checker, and put back at once if the
  result fails.
- **The turn-arrows jar only goes on firmware where it is known to work.** It
  replaces parts of the unit's interface; on firmware it does not fit, the
  centre screen may not start.
- **Originals are kept**, on the unit and on the card. Nothing in `/lib` or
  `/usr/lib` is touched.

If the centre screen stays black after a reboot, the Java interface did not
start and the green menu is unavailable. Over SSH:

```sh
mount -uw /mnt/app
ls -t /mnt/app/eso/hmi/lsd/lsd.sh.before_*        # newest first
cp /mnt/app/eso/hmi/lsd/lsd.sh.before_<newest> /mnt/app/eso/hmi/lsd/lsd.sh
```

then reboot. If Android Auto itself will not start, the original supervisor
file is `/mnt/system/etc/eso/production/smartphone_integrator.json.gal-dualscreen.original`
(and in `ClusterMap/backups/` on the card). Keep the card until you have
driven with the install for a while.

No software can promise a modified head unit always recovers. These steps
cover the failures seen or foreseen so far.

## Getting your unit added

Each firmware needs a profile, worked out from a few of its files, and an
owner willing to test.

1. Run the update (route 1). On a unit it does not support, it installs
   nothing and copies the files into `ClusterMap/porting_<train>/`, about
   3.2 MB. Or use the `COLLECT` marker, or the green menu's **Collect files
   for porting**.

   It copies the two phone libraries under whatever names the unit carries
   them: the Android Auto receiver (`libautoreceiver.so`, or
   `libautoreceiver_qnx.so.1` on the VWG11 generation) and the CarPlay
   library (`libairplay.so`). If neither known name is there it searches the
   unit and copies what it finds, because a differently named library is the
   usual reason a unit looks unportable when it is not (#28). `info.txt`
   records which names were found.
2. Open an issue with your car, the firmware train, and `info.txt` from that
   folder.
3. **Do not post the other files.** They are Volkswagen and Harman software,
   not ours to distribute; they go to the porter privately.

The folder holds no account data, phone names or VIN. The porter's side is in
[Development](Development.md#adding-a-firmware).
