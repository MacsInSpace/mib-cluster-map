# Install guide

First time? Use the [Quick start](Quick-Start.md) instead. This page is the
reference: requirements, both install routes, settings, and recovery.

This describes the build in this fork, which uses an open toolchain and adds
several fixes to upstream. Status: working on one car. The cluster map ran for eight minutes at about 30
frames per second, with and without a route, through repeated input tests, with
no drops. Longer drives, reconnects, reverse-camera use and waking from sleep
are not yet tested.

## 1. Will it fit your car

All of these must be true. The hook checks the last one itself and leaves
Android Auto stock if it fails.

| Requirement | How to check |
|---|---|
| Harman MIB2.5 "Discover Pro" head unit | 9.2 inch glass screen, part number like `5NA 035 045` |
| Digital cluster (Active Info Display) | the cluster can show the VW navigation map |
| Firmware `MHI2_ER_VWG13_P4521`, software 1367 | "Software: 1367" on the System information screen is necessary but not sufficient; see [Supported units](Supported-Units.md) |
| MQB Coding MIB2 Toolbox | Optional for route 0, required for routes A and B. Recommended in any case, with its SSH service: it is the way back in if the screen ever fails to start |
| NavActiveIgnore patch | Added by the installer if missing, on tested firmware. Elsewhere apply it from the toolbox: `Customization` > `Navigation` > "Ignore navigation-active status from smartphone" |

Other firmware trains are **not** supported. The hook contains fixed addresses
inside the stock `gal` program. On a mismatch its log says
`event=firmware.verify result=failed` and nothing else happens. Porting to
another train means re-deriving those addresses; see [Receiver layout verification](Receiver-Layout-Verification.md)
for the method used on this unit; `tools/armre.py` is the helper it mentions.

## 2. Get the package

Download the release zip that matches the firmware and extract it to the root
of a FAT32 SD card. You get two folders:

```text
AAClusterMap/            everything this project installs or runs
Custom/GreenMenu/        one menu screen for the MQB Coding MIB2 Toolbox
```

The card must also hold the MQB Coding MIB2 Toolbox files: the toolbox only
imports custom screens from a card that has its `Toolbox` folder. Merge the
`Custom` folders; nothing is overwritten. Use slot 1 and leave slot 2 empty. To build the package yourself, see "Building" at the end.

## 3. Install

Keep the engine running or a charger connected. Hours of ignition-on testing
flattened a healthy battery during development, and low voltage produces
unrelated dash warnings ("Proactive occupant protection restricted",
"Manoeuvre braking restricted").

### Route 0: as a software update (no toolbox, no SSH)

Status: built on the toolbox's own update mechanism, **not yet tested on a
car**. Steps are in the [Quick start](Quick-Start.md). The card's
`metainfo2.txt` names `AAClusterMap/final/finalScript.sh` as the update's
final script; it runs `GEM/install.sh`, the same script as the green menu
entry, and writes its output to `AAClusterMap/update_result.txt`. With a file
whose name starts with `UNINSTALL` in `AAClusterMap`, it runs the uninstall
instead. A ready-made one ships in a subfolder.

After a successful install the final script also switches on the unit's
engineering menu (the same setting the toolbox turns on), so the screen the
update copied is reachable. On unsupported firmware it installs nothing and
runs the file collection instead.

### Route A: from the green menu (no SSH)

Status: written to the toolbox's documented custom-screen format, **not yet
tested on a car**. Route B is the tested one.

1. SD card in **slot 1**. Open the green engineering menu.
2. `MQBCoding` > `Customization` > `GreenMenu` > **Install GreenMenu screens
   and scripts from Custom/GreenMenu**. The toolbox copies the screen to the
   unit. A message about a missing `scripts` folder is harmless.
3. Leave and re-enter the green menu. Go to
   `AAClusterMap` (top level of the green menu).
4. Run **1. Status and compatibility check**. It must say the firmware is supported.
5. Run **2. Install cluster map** and wait for `AACLUSTER_INSTALL_OK`.
6. Hold the power button for ten seconds to reboot.

### Route B: over SSH

SD card in slot 1, laptop on the car's wifi hotspot, SSH in as root.

```sh
mount -uw /fs/sda0
sh /fs/sda0/AAClusterMap/enable_hook.sh
```

Then hold the power button for ten seconds to reboot.

### What the installer changes

| Where | What |
|---|---|
| `/mnt/system/etc/eso/production/smartphone_integrator.json` | adds the preload entries to the `gal` child; original saved beside it as `.gal-dualscreen.original` |
| `/mnt/app/eso/lib/gal_dualscreen/` | hook library, helper library, a copy of the settings file |
| `/mnt/app/navigation/stream-player` | the video player |
| `/mnt/app/eso/hmi/lsd/lsd.sh` | only if `VCAndroidAuto.jar` is loaded: its one line is removed, previous file saved as `lsd.sh.before_VCAndroidAuto`. Uninstalling puts it back. If NavActiveIgnore is missing its one line is added, previous file `lsd.sh.before_NavActiveIgnore`; uninstalling removes it again |

A copy of the original supervisor file is also written to
`AAClusterMap/backups/` on the card. Keep it.

## 4. Test and collect logs

1. Wait about two minutes after boot.
2. Plug the phone in, open Google Maps in Android Auto, put the cluster in map view.
3. Start a route.
4. If something is wrong, save the logs **before** rebooting: green menu
   **Save logs to SD**, or `sh /fs/sda0/AAClusterMap/collect_logs.sh`. They
   land in `AAClusterMap/run_logs/`.

The logs are in RAM on the unit and are lost at the next reboot.

The menu also has **Collect files for porting**, which is only for owners of
other firmware; see [Supported units](Supported-Units.md).

**Before posting logs publicly, read them.** `sloginfo.txt` is the unit's
system log and can contain paired phone names, Bluetooth addresses and other
details of your car.

## 5. Uninstall and restore the original state

Green menu **Uninstall and restore original state**, or:

```sh
mount -uw /fs/sda0
sh /fs/sda0/AAClusterMap/disable_hook.sh
```

Then reboot. This is a full revert:

- the saved supervisor file is put back;
- the hook, helper library, settings copy and player are deleted;
- if the installer took out the turn-by-turn jar's start-up line, that line is
  put back;
- if the installer added NavActiveIgnore, it is taken out again.

Afterwards the unit is as it was before the install. Run the status check to
confirm it says "Hook: not installed".

## 5a. Turn-by-turn arrows instead of the map

If the map does not suit you, or you prefer arrows, the package can switch the
cluster to the simpler turn-by-turn display from
[adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc):
next-turn arrow, distance, and track information, drawn by the cluster itself.

Green menu **Switch to turn-by-turn arrows instead (no map)**, or:

```sh
sh /fs/sda0/AAClusterMap/disable_hook.sh --keep-jar-removed   # only if the map is installed
sh /fs/sda0/AAClusterMap/turn_by_turn.sh install
```

Then reboot. The two cannot run together: with the arrows jar loaded, the
cluster map goes blank when a route starts. To go back to the map, run
**Install cluster map** again; it turns the arrows off. To remove the arrows
without installing the map: `sh /fs/sda0/AAClusterMap/turn_by_turn.sh remove`.

The jar is the unmodified 0.1.4 release, MIT licensed. Its author lists
`MHI2_ER_VWG13_P4521` and `MHI2_ER_VWG13_K4525` as tested; the menu entry
refuses other firmware.

## 6. Settings you may need to change

Edit `AAClusterMap/gal_dualscreen.conf` on the SD card, then run the installer
again so the copy on the unit is refreshed, and reboot. The unit reads its own
copy, so the card does not need to stay in the slot.

| Setting | Shipped value | Change it when |
|---|---|---|
| `GAL_SECONDARY_DPI` | 125 | map text and turn card are too big (lower) or too small (higher) |
| `GAL_SECONDARY_INSETS` and `GAL_SECONDARY_UI_CONFIG_HEX` | 40,40,127,127 | map controls are hidden behind the dials. The hex value overrides the insets, so change both or delete the hex line |
| `GAL_SECONDARY_UI_THEME` | 2 (dark) | 0 follows the phone, 1 is light |
| `GAL_DUALSCREEN_AAP_MINOR` | 7 | never, unless testing: the phone only offers the cluster display at this value |
| `GAL_FIX_SUPPRESS_UNEXPECTED` | on | never, unless reproducing the connection loop |
| `GAL_DUALSCREEN_DEBUG`, `GAL_FIX_STREAM_TIMING`, `GAL_PLAYER_STATS`, `GAL_HOOK_LOG_MAX_MB` | 0, 0, 0, 1 | troubleshooting: see "Logging" below |

### Logging

The shipped install is quiet: no per-frame lines, no once-a-second timing or
player statistics, and a 1 MB cap. A short log of connects, state changes and
errors is still kept in RAM (`/tmp/gal_dualscreen.log`, `/tmp/stream-player.log`)
so a failure can be diagnosed with `collect_logs.sh`. It is lost at reboot and
never written to flash.

For a full trace: set `GAL_FIX_STREAM_TIMING=1`, `GAL_PLAYER_STATS=1` and
`GAL_HOOK_LOG_MAX_MB=10` in `gal_dualscreen.conf`, then reinstall over SSH with
`sh /fs/sda0/AAClusterMap/enable_hook.sh --debug` and reboot. To write no hook log at all,
add `GAL_HOOK_LOG=/dev/null`.

## 7. Known open issues

| Symptom | State |
|---|---|
| Connection loop, phone disconnects every ~17 s | Fixed. See [Navigation status messages](Navigation-Status-Messages.md) |
| Map is solid with no route, goes blank when a route starts | Fixed. Caused by `VCAndroidAuto.jar`; the installer removes that jar's start-up line. Confirmed on the car |
| Turn arrows from `VCAndroidAuto.jar` do not update | Expected for now: the newer navigation messages are ignored, not translated |
| No steering-wheel zoom of the cluster map | Not possible with any input found. See [Cluster zoom findings](Cluster-Zoom-Findings.md) |

### The turn-by-turn jar is turned off by the installer

On the test car the map was solid with no route and went blank the moment a
route started, while `VCAndroidAuto.jar` was loaded. The installer therefore
checks the Java start-up script and:

- adds NavActiveIgnore if it is missing (tested firmware only; elsewhere it warns);
- removes the one line that loads `VCAndroidAuto.jar`, keeping the previous file.

Uninstalling puts that line back. `enable_hook.sh --keep-turn-by-turn` skips
the removal. If a car still blanks without that jar, try
`GAL_FIX_HIDE_NAV_STATUS=1` in `gal_dualscreen.conf` (untested).

## 8. Safety and recovery

What the scripts do to avoid leaving a unit that will not start:

- **Wrong firmware is refused** before anything is written, and the hook checks
  again each time Android Auto starts. On a mismatch it does nothing.
- **Only two existing system files are ever edited**: the smartphone supervisor
  configuration and the Java start-up script. Each new version is written to a
  separate file, checked, and only then moved into place in one step.
- **The supervisor file is validated** with the unit's own JSON checker before
  and after. If the result fails, the original is put back immediately.
- **The start-up script edit is one line**, and is refused unless the result
  still contains the main class path, the Java launch line and an unchanged
  NavActiveIgnore line.
- **Originals are kept on the unit and on the SD card.** Nothing in `/lib` or
  `/usr/lib` is touched, and no stock file is replaced by a different program.

What you should do:

- Run **Status and compatibility check** first and stop if it says unsupported.
- Keep stable power. Never switch the ignition off while a script is running.
- Keep the SD card, with its `AAClusterMap/backups/` folder, until you have
  driven with it for a while.

If something goes wrong:

| Symptom | What to do |
|---|---|
| Android Auto does not start, or keeps reconnecting | **Uninstall and restore original state**, then reboot |
| Cluster map blank or frozen | Unplug and replug the phone. If it persists, save logs, then uninstall |
| The centre screen stays black after a reboot | The Java interface did not start, so the green menu is unavailable. Connect over SSH, which does not need the screen, and restore the previous start-up script: `cp /mnt/app/eso/hmi/lsd/lsd.sh.before_NavActiveIgnore /mnt/app/eso/hmi/lsd/lsd.sh` (or `.before_VCAndroidAuto`, whichever is newest) after `mount -uw /mnt/app`, then reboot. This is why having the toolbox's SSH service installed beforehand is strongly recommended, even if you install from the green menu |
| Nothing above helps | The supervisor original is at `/mnt/system/etc/eso/production/smartphone_integrator.json.gal-dualscreen.original` and in `AAClusterMap/backups/` on the card |

No software can promise a modified head unit will always recover. These steps
cover the failures seen or foreseen so far.

## Building

Needs Docker. On Apple Silicon the toolchain runs under emulation.

```sh
# a) the cross compiler image (about ten minutes, once)
git clone https://github.com/luka-dev/qnx65-armv7-toolchain
cd qnx65-armv7-toolchain && ./host-scripts/qnx-run.sh build 8.5
# if ftp.gnu.org refuses connections, replace it in the Dockerfile with
# https://mirrors.kernel.org/gnu/ (the checksums are pinned, so this is safe)

# b) this project
cd ../<this repo> && ./build_local.sh
```

Result: `dist/sdcard/` and a release zip in `dist/`. FFmpeg 6.1.5 is downloaded
and built on first use. The upstream Makefiles, which need a private toolchain
image, are kept unchanged for reference.
