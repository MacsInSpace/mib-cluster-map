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
3. Put it in **SD slot 1**, with slot 2 empty.

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

| Entry | What it does |
|---|---|
| 1. Status and compatibility check | Firmware train, verdict, what is installed, Java patches |
| 2. Install cluster map | The same installer as route 1 |
| Uninstall and restore original state | Full revert |
| Switch to turn-by-turn arrows instead (no map) | Removes the map, installs the arrows. Install switches back |
| Save logs to SD | For a problem report. Before rebooting: logs are in RAM |
| Collect files for porting (quick) | About 2.5 MB, read only |
| Collect for porting, with Java image (55 MB, slow) | Only for a turn-arrows port |

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
it. Android Auto's cluster video is always 800×480, so where the window has
another shape the phone is asked to leave margins (0×182 for 1010×376) and
the player scales the rest to fill the window. CarPlay is asked for the
window's size. If the size cannot be read, the card's `GAL_PLAYER_WINDOW`
is used when set (for example `GAL_PLAYER_WINDOW=1010x376`), otherwise the
usual size for the make (1010×376 on SEAT and Skoda, 800×480 on VW and
anything else). The install
output and the unit's copy of the settings (`GAL_PLAYER_WINDOW`,
`GAL_SECONDARY_MARGINS`) show what was chosen.

The display manager only lists window 33 once the cockpit has shown it, so
the installer can be left with a guess. The player therefore reads the size
again each time it starts. If it differs, it opens the window at the real size
and corrects the two settings for the next start. Until then the picture can
have black bars. CarPlay's size only changes on the next install.

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

| Setting | Shipped | Change it when |
|---|---|---|
| `GAL_SECONDARY_DPI` | auto | map text and turn card too big (lower) or too small (higher). `auto` is the value owners settled on for your make: SEAT 125, Skoda 125, VW 138, Audi A4 B9 140, otherwise 125. A number here is kept as it is |
| `GAL_PRIMARY_DPI` | unset (the unit's own) | Android Auto on the **centre screen** looks too large or too small. 60 to 400, the unit's own is usually 213; lower shows more. The same as aawireless's DPI setting, but kept in passthrough mode. Remove the `#` in front of the line. Car-tested in #71 |
| `GAL_SECONDARY_INSETS` | auto | map controls or the ETA hide behind the dials or a warning light. Top, bottom, left, right; each 0 to 127. `auto` is SEAT `105,127,127,127`, Skoda `40,127,127,127`, VW `52,82,127,127`, Audi A4 B9 and otherwise `40,40,127,127`. They also set where CarPlay keeps its card. See the settings owners have settled on, below |
| `GAL_SECONDARY_UI_THEME` | 0 (follows the headlights) | you want the cluster map always dark (2) or always light (1). Waze stays dark whatever is set. 1 or 2 costs two bytes of the insets message, so fewer insets can go above 127 |
| `CLUSTERMAP_KEEP_SETTINGS` | unset (keep) | you want a clean install. Each install remembers the lines you changed in `gal_dualscreen.conf` and puts them back at the next install wherever the new card still has the shipped default; a line changed on the new card wins, and `update_result.txt` lists what was kept. When you install the same release again, a setting you have edited on the card since the last install is used as the card has it, so a line you switch off stays off. `0` installs only the card's settings: use it once if a setting from an older release keeps coming back. Settings from v1.1.1 and betas before beta19 are not carried over. The uninstall forgets them |
| `CLUSTERMAP_FULL_FRAME` | 0 | the map looks soft on a wide window (SEAT, Skoda, Audi). 1 has the phone draw on the whole 800×480 frame with wide pixels instead of leaving margins: more detail, same layout. Also a green-menu switch ("Sharper map"), so it can be tried in the car. From AMDFX60's fork, car-tested on his Skoda Superb (#56) |
| `GAL_PLAYER_PRIORITY` | unset | the cluster map stutters when the unit is busy. 12 raises the player a little above the default 10; it never lowers it. Not car-tested |
| `GAL_DUALSCREEN_AAP_MINOR` | 5 | the Android Auto version the unit claims (1.x). The map shows at 2 to 7. At 6 or higher Google Maps sends newer navigation messages this unit cannot read; the hook translates them into the old ones (`GAL_DUALSCREEN_NAV_TRANSLATE`, on), so the arrows jar should keep its turn pictograms. Not yet car-tested above 5 (#4) |
| `GAL_PLAYER_WINDOW` | unset | the installer says the cluster map window was not listed and guessed wrong. It assumes `1010x376` on SEAT and Skoda and `800x480` on VW, but some VW cockpits are `1010x376` (#52) |
| `GAL_VC_CONTEXT` | 70 | the cockpit map is in another display context. 70 on VW, SEAT and Skoda; on an Audi A4 B9 (`AUG22`) the installer uses 72 by itself (#14) |
| `CLUSTERMAP_KEEP_ARROWS` | 0 | 1 keeps the turn-arrows jar with the map (adds it if missing): map, arrows and music together on SEAT. Leave it at 0 on VW: the map has gone blank when a route starts, and a Golf `P4521` cockpit switched to its own arrow view after a few presses of OK and stayed there until the arrows were removed. One Tiguan `K4525` reports both working (#44) |
| `CLUSTERMAP_MUSIC_INFO` | 0 | 1 shows the track playing (title, artist, cover) on the cockpit's media screen with the map; with CarPlay, title, artist and album instead of "Apple CarPlay". A music-only build of the arrows jar that sends no turn data, so the map stays up on a route. On `P4521`, `K4525`, `P4708` and `P4709`; ignored with `CLUSTERMAP_KEEP_ARROWS=1`. Not car-tested yet |
| `CLUSTERMAP_TURN_INFO` | 0 | 1 sends Android Auto's turn info (arrow, distance) to the cockpit with the map: a build of the arrows jar that, unlike `CLUSTERMAP_KEEP_ARROWS=1`, never switches the cockpit to its arrow view, so the cockpit should draw its own arrow beside the map. Includes the track info of `CLUSTERMAP_MUSIC_INFO` and wins if both are set. Same trains; ignored with `CLUSTERMAP_KEEP_ARROWS=1`. Tested on a Golf R `P4521`: map kept, arrow in the right dial, road name above the map |
| `CLUSTERMAP_TURN_TEXT` | auto | with `CLUSTERMAP_TURN_INFO=1`, the road name shows twice with the map (the cockpit's line above Google's card). `auto` sends it only while the cockpit shows no map, `always` every time, `never` not at all (arrow and distance only). Not car-tested yet |
| `CLUSTERMAP_ADD_NAVIGNORE` | 0 | the map goes as soon as a route starts, on firmware where the installer does not add `NavActiveIgnore` by itself. 1 adds it, with a backup, and uninstall removes it. It edits the script that starts the centre screen, so check SSH works first. Ignored on `VWG11` S-trains (`S2125`, where it stopped Android Auto, #39) and Audi `AUG22`. Works on `VWG11` `K3342` (#39, #28). On K3342 with a wireless CarPlay adapter, one owner's CarPlay dropped seconds after connecting with it loaded (#62, cause not confirmed) |
| `CLUSTERMAP_CARPLAY` | 1 | a wireless CarPlay adapter drops, or loses the cockpit map, with the CarPlay map installed. 0 installs the Android Auto map only and leaves CarPlay stock (#55, #56) |
| `CLUSTERMAP_CARPLAY_TRIAL` | unset | for developers: allows the CarPlay map on another `libairplay.so` build. The hook's checks do not prove a build fits, so do not use it on `857735` (Audi `K3346`, VWG11 `K3342`). See [CarPlay](CarPlay.md) |
| `CLUSTERMAP_CARPLAY_SCALE` | 100 | the CarPlay map looks too zoomed in (above 100: smaller text, more map) or too small (below 100). Declares the display this many percent larger in millimetres, which the iPhone sizes its UI from; 70 to 200, try 130 then 160. Remove the `#` in front of the line. DPI does not affect CarPlay |
| `CLUSTERMAP_CARPLAY_FRAME_SCALE` | 100 | as above, the beta13 way: a larger frame shrunk into the window, 100 to 200. Costs frame rate. Replaces `CLUSTERMAP_CARPLAY_SCALE` when set |
| `CLUSTERMAP_CARPLAY_INSETS` | unset | CarPlay's arrival line or card is cut off by the dials. Top, bottom, left, right like `GAL_SECONDARY_INSETS`, but for CarPlay only, so the Android Auto map stays as it is, and each may go above 127. Unset, CarPlay uses `GAL_SECONDARY_INSETS`. Raise the second number in small steps: too large and the iPhone drops the arrival line altogether. On SEAT, `130,155,127,127` with `CLUSTERMAP_CARPLAY_FRAME_SCALE=160` works (#19) |
| `CLUSTERMAP_CARPLAY_ZOOM` | not sent | trial: tells the iPhone the cockpit's zoom factor, 50 to 200 (the SEAT MU1409 port sends 70). Below 100 may show more map. Not car-tested with this project |
| `CLUSTERMAP_CARPLAY_VIEW` | unset | CarPlay's card or map is not what you want on the cockpit: `full` (map and card), `map` (map only) or `card` (card only) |
| `CLUSTERMAP_CARPLAY_SPEEDLIMIT`, `_COMPASS`, `_ETA`, `_CARD_POSITION` | unset | to turn CarPlay's speed limit, compass or arrival time on the cockpit on or off (`yes`/`no`), or move its card (`left`, `right`, `top`, or `iphone` to let the iPhone decide). Unset, the iPhone decides, except on SEAT, where the card goes to the top (it keeps the car centred during a route, #19) |
| `GAL_PLAYER_DECODER` | sw | `sw` is the tested software decoder. `hw` uses the unit's own video decoder and frees most of a processor core. If it will not open, the player uses software; if it fails while decoding, it stays off until the next reboot. **Not yet car-tested** |
| `GAL_PLAYER_NVSS_OUTPUT` | 1 | the cluster stays black with `hw`: try 0 (uncomment the line first) |
| `GAL_DUALSCREEN_DEBUG`, `GAL_FIX_STREAM_TIMING`, `GAL_PLAYER_STATS`, `GAL_HOOK_LOG_MAX_MB` | 0, 0, 0, 1 | full trace for a bug report: 0, 1, 1, 10, then install over SSH with `enable_hook.sh --debug` |

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
| Skoda 1010×376 (`P4526`), *auto* | 125 | `40,127,127,127` | raskrivuska, #15 |
| Audi A4 B9 1440×455 (`K3346`), *auto* | 140 | `40,40,127,127` | mariuszhejnold-arch, #14 |
| Audi A3/S3 8V 1440×455 (`P5089`), *auto* | 140 | `40,40,127,127` | kashavsehra, #51 (window `1440x455`, margins 0×227, context 70) |
| Audi A3/S3 8V 1440×455, **Sharper map ON** | 100 | `60,150,10,10` | kashavsehra, #51 and #78 (with `CLUSTERMAP_FULL_FRAME=1`; smaller cards, car centred) |
| Audi A7 C7.5 800×298 (`K3663`), *auto* | 125 | `40,40,127,127` | Seif, by email (context 73) |
| VW 12.3 in, ETA card showing (`K4525`) | 138 | `52,82,127,127` | totocastellano-cmd, #20 and #12 (`53,83,127,127` on a second car: the same within a pixel) |
| VW 12.3 in Passat B8 2019 (`K4525`), ETA card showing, with `GAL_SECONDARY_UI_THEME=0` | 138 | `56,73,127,127` | danielszyszko-ui, #41 |
| VW Golf (`P4521`), ETA card showing, Google Maps and Waze, *auto* for VW | 138 | `52,82,127,127` | tvarszegi1, #8, road-tested |
| VW Passat B8 2018 (`P4512_1`), small and large dials, *auto* for VW | 138 | `52,82,127,127` | slechtaadam-byte, #47 |

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
| CarPlay works on the centre screen through a wireless adapter, but the cockpit keeps the car's map | Try a cable. Many adapters never open the iPhone's second screen, which the cockpit map needs ([CarPlay](CarPlay.md#wireless-adapters)) |
| A wireless adapter connects, then drops every few seconds | In the adapter's own app: automatic standby **off**, VAG crash fix **off** (that fix is for VAG *Technisat* units, not Harman), adapter firmware up to date (#12, #35) |
| The phone keeps disconnecting | Save logs, uninstall, reboot, open an issue |
| The map appears, then goes blank when a route starts, or the cluster says "navigation on mobile device is active" | `NavActiveIgnore` is not loaded. The installer adds it on `P4521`, `K4525`, `P4512`, US `P3662`, Skoda `P4526` and SEAT `P4709`. On any other firmware set `CLUSTERMAP_ADD_NAVIGNORE=1` and install again, or apply it from the MIB2 Toolbox (**Customization > Navigation > Ignore navigation-active status**). Check SSH works first — see [Safety and recovery](#safety-and-recovery) |
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
