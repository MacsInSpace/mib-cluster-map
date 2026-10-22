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
   └── _Swdlautorun.txt off; rename to start the update without the menu (below)
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

**Without the service menu (for cars where it is hard to reach, such as an
Audi without developer mode; tested on a VW Golf, untested on Audi):** rename
`_Swdlautorun.txt`, at the top of the card, to `Swdlautorun.txt` and insert
the card. Units that honour it start this update by themselves (the trigger
M.I.B. uses); the Golf started it straight away. The update renames the file back, so it does not start again after the
restart. If nothing happens within two minutes, the unit does not honour it:
use the menu.

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
| `COLLECT.txt` | `to only check compatibility, move this file up one folder` | changes nothing: writes the status check to `update_result.txt` and collects the porting files. Only the menu screen file is copied to the unit |

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
| `/mnt/app/eso/hmi/lsd/lsd.sh` | Java patch lines: NavActiveIgnore added if missing, the turn-arrows jar's line removed (map) or added (arrows). Previous file kept as `lsd.sh.before_<jar>` |
| `/mnt/app/eso/hmi/engdefs/cluster-map.esd` | the menu screen |
| `/mnt/system/etc/pf*.conf` | CarPlay map only: one firewall rule letting the iPhone's cluster video (TCP 6031) in on its USB CarPlay link, marked `# clustermap carplay map`; originals kept as `.clustermap.original` |
| `/mnt/app/root/mibr-carplay111-safearea.conf` | CarPlay map only: the part of the window clear of the dials, from `GAL_SECONDARY_INSETS` |

Uninstall puts all of it back, except that the engineering menu stays
switched on, which is harmless. Run the status check afterwards: it should say
the hook is not installed.

## Cluster map window

The cluster only shows the head unit's map window at that window's own size:
800×480 on the Golf, 1010×376 on some SEAT and Skoda clusters. A window of
another size arrives as coloured stripes. The installer reads the size from
the display manager (`dmdt gd`, window 33) and opens the player's window at
it. Android Auto's cluster video is always 800×480, so where the window has
another shape the phone is asked to leave margins (0×182 for 1010×376) and
the player scales the rest to fill the window. CarPlay is asked for the
window's size. If the size cannot be read, 800×480 is used. The install
output and the unit's copy of the settings (`GAL_PLAYER_WINDOW`,
`GAL_SECONDARY_MARGINS`) show what was chosen.

## Settings

Edit `ClusterMap/gal_dualscreen.conf` on the card, run the install again so
the unit's copy is refreshed, and reboot. The file documents every key.

| Setting | Shipped | Change it when |
|---|---|---|
| `GAL_SECONDARY_DPI` | 125 | map text and turn card too big (lower) or too small (higher) |
| `GAL_SECONDARY_INSETS` | 40,40,127,127 | map controls or the ETA hide behind the dials or a warning light. Top, bottom, left, right; each 0 to 127. One Golf owner prefers 53,47,127,127 |
| `GAL_SECONDARY_UI_THEME` | 2 (dark) | 0 follows the phone, 1 is light |
| `GAL_PLAYER_DECODER` | sw | `sw` is the tested software decoder. `hw` uses the unit's own video decoder and frees most of a processor core. If it will not open, the player uses software; if it fails while decoding, it stays off until the next reboot. **Not yet car-tested** |
| `GAL_PLAYER_NVSS_OUTPUT` | 1 | the cluster stays black with `hw`: try 0 (uncomment the line first) |
| `GAL_DUALSCREEN_DEBUG`, `GAL_FIX_STREAM_TIMING`, `GAL_PLAYER_STATS`, `GAL_HOOK_LOG_MAX_MB` | 0, 0, 0, 1 | full trace for a bug report: 0, 1, 1, 10, then install over SSH with `enable_hook.sh --debug` |

Logs are kept in RAM only (`/tmp/gal_dualscreen.log`, `/tmp/stream-player.log`)
and lost at reboot. **Save logs to SD** copies them, with the system log, to
a new numbered folder in `ClusterMap/run_logs/` each time. Read them before posting: the system log can contain
phone names and Bluetooth addresses.

## If it does not work

| What you see | What to do |
|---|---|
| The car's own map, or "no map" | Check the cluster is in map view. Unplug the phone, wait ten seconds, plug it in |
| The phone keeps disconnecting | Save logs, uninstall, reboot, open an issue |
| The map appears, then goes blank when a route starts | Run the install again: something re-enabled the turn-arrows jar |
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
   2.5 MB. Or use the `COLLECT` marker, or the green menu's **Collect files
   for porting**.
2. Open an issue with your car, the firmware train, and `info.txt` from that
   folder.
3. **Do not post the other files.** They are Volkswagen and Harman software,
   not ours to distribute; they go to the porter privately.

The folder holds no account data, phone names or VIN. The porter's side is in
[Development](Development.md#adding-a-firmware).
