# Quick start: from a blank SD card to the map on your cluster

A step-by-step walkthrough for someone who has not modified a head unit
before. It takes about 20 minutes. Read it through once before starting.

> [!CAUTION]
> You are changing system files on your car's head unit. Do it parked, with the
> engine running or a battery charger connected, and never switch the ignition
> off while something is installing. If any step does not look like the
> description, stop and ask before continuing.

There are two ways to install. Both end in the same place.

| | Way 1: software update | Way 2: green menu |
|---|---|---|
| Needs the toolbox installed first | No | Yes |
| What you do | Run one update from the SD card | Add a menu screen, run a check, press Install |
| You see a compatibility verdict before anything changes | No, but the installer still refuses unsuitable firmware and writes the reason to the card | Yes |
| Tested on a car | **Not yet** | **Not yet** (the same installer run over SSH is) |

Way 1 is the least effort, and it also puts the `AAClusterMap` menu screen on
the unit. Way 2 is for people who already live in the toolbox's menu.

## What you need

- A car with the **Discover Pro 9.2 inch** head unit and a **digital cluster**.
- An **SD card**, 2 GB to 32 GB. Cards larger than 32 GB are awkward to format
  correctly, so avoid them.
- A computer with an SD card reader.
- An **Android phone** and a USB cable that already works with Android Auto in
  this car.
- About 20 minutes when you can stay parked.

## Step 1: check your head unit

On the head unit: `MENU` > `Setup` > `System information`.

You need **Software: 1367**. If it shows anything else, this release does not
support your unit yet; see the [support matrix](Firmware-Support-Matrix.md).

"1367" is necessary but does not prove the firmware is the right one. The
installer does the real check itself and changes nothing if it fails.

## Step 2: prepare the SD card

1. **Format the card as FAT32.** This erases it.
   - Windows: right-click the card in File Explorer > `Format` > File system
     `FAT32` > `Start`.
   - macOS: Disk Utility > select the card (the device, not the volume) >
     `Erase` > Format `MS-DOS (FAT)`, Scheme `Master Boot Record`.
2. Download the zip from this repository's [Releases](../../../releases) page
   and extract it.
3. Copy **everything inside** the extracted folder to the card, so the top
   level of the card looks like this:

```text
(SD card)
├── AAClusterMap/        the installer, programs, settings and guides
├── Custom/              the menu screen, for the green menu way
└── metainfo2.txt        tells the head unit this card is an update
```

4. Eject the card properly and put it in **SD slot 1** of the head unit. Make
   sure the other SD slot is **empty**.

## Way 1: install as a software update

1. Hold the **MENU** button until the service screen appears. It takes several
   seconds.
2. Choose `Software updates/versions`, then `Update` in the top right corner.
3. Choose the SD card, then **`Android Auto Cluster Map`**.
4. Let the update run. Do not switch the ignition off. The unit may restart.
   It then shows a list of modules, most marked `N/A`; press the back button
   in the top right.
5. If it asks you to connect a computer and clear error codes, press `Cancel`.
   That is not needed.
6. When the unit is back at the home screen, **hold the power button for ten
   seconds** to reboot it once more.

What the update did, without asking:

- copied the `AAClusterMap` menu screen to the unit;
- checked the firmware, and stopped if it is not supported;
- added the NavActiveIgnore patch if it was missing (supported firmware only);
- switched off the turn-by-turn arrows jar if it was loaded;
- installed the cluster map;
- switched on the unit's engineering ("green") menu, so you can reach that
  screen: hold MENU > `Testmode` > `Green Developer Menu` > `AAClusterMap`. It
  offers status, logs, uninstall and the turn-arrows switch.

**If your firmware is not supported**, nothing is installed. The update
instead copies the files a port would need into a `porting_...` folder on the
card. See [Supported units](Supported-Units.md) for what to do with it.

To see what happened, put the card in a computer and open
`AAClusterMap/update_result.txt`. It ends with `AACLUSTER_INSTALL_OK`, or says
why nothing was installed. Go to "Use it" below.

**To uninstall this way:** put the card in a computer. Inside `AAClusterMap`
there is a folder called `to uninstall, move this file up one folder`. Move
the `UNINSTALL.txt` file in it up into `AAClusterMap` itself, then run the same
update again. It removes everything and restores the original state. Move the
file back, or delete it, before installing again.

The file only means something to this package, and only in that folder.

The screens in steps 2 to 5 are described from the toolbox's instructions for
its own update, which uses the same mechanism. If yours look different, tell
us in an issue.

## Way 2: install from the green menu

Use this if you already have the
[MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) installed,
or want its menu. To install the toolbox, follow its README; it is its own
software update from its own SD card.

If you used Way 1, the screen is already there: skip to step 4. Otherwise the
card must hold the toolbox's files as well as ours: copy the toolbox's files
to the card first, then `AAClusterMap` and `Custom`, merging the `Custom`
folders. **Leave the toolbox's `metainfo2.txt` in place; do not
replace it with ours.**

1. Hold the **MENU** button until the service screen appears, choose
   `Testmode`, then `Green Developer Menu`. The screen turns green with white
   text. On older software, keep holding MENU for about ten seconds to reach
   the developer menu.
2. Open **`mqbcoding`** > `Customization` > `GreenMenu` and run **Install
   GreenMenu screens and scripts from Custom/GreenMenu**. A message about a
   missing `scripts` folder is harmless.
3. Leave the green menu completely (press `MENU` or `HOME`) and open it again.
4. Go to **`AAClusterMap`** (top level of the green menu) and run
   **1. Status and compatibility check**.

| It says | What to do |
|---|---|
| `supported: yes (tested firmware)` | Continue |
| `supported: yes (UNTESTED firmware ...)` | It may work, but nobody has tried your firmware. Continue only if you accept that, and please report the result |
| `supported: NO` | Stop. Nothing has been changed. Consider **Collect files for porting**; see [Supported units](Supported-Units.md) |

5. Run **2. Install cluster map** and wait for **`AACLUSTER_INSTALL_OK`**. It
   adds the NavActiveIgnore patch itself if needed.
6. Leave the green menu and **hold the power button for ten seconds** to reboot.

Everything in the green menu is powerful. Do not change entries this guide
does not mention.

**Recommended while you are there:** `Customization` > `Advanced` > **Install
SSHD service**. It is your way back into the unit from a laptop if the screen
ever fails to start. See the toolbox's
[SSH login guide](https://github.com/jilleb/mib2-toolbox/wiki/SSH-Login).

## Use it

1. Wait about two minutes after the unit has started.
2. Plug in the phone and let Android Auto start on the centre screen.
3. Open Google Maps or Waze in Android Auto.
4. On the cluster, switch to the **map view** with the steering wheel buttons,
   the same view that shows the built-in navigation map.

The phone's map should appear on the cluster within a few seconds, and stay
there when you start a route.

## If it does not work

| What you see | What to do |
|---|---|
| The cluster shows the car's own map, or "no map" | Check the cluster is in map view. Unplug the phone, wait ten seconds, plug it in again |
| Android Auto keeps disconnecting | Uninstall (green menu **Uninstall and restore original state**, or the uninstall update), reboot, and open an issue. With the green menu, run **Save logs to SD** first |
| The map appears, then goes blank | Run the install again (either way) and reboot. It switches off the turn-by-turn jar if something re-enabled it |
| You want it gone | Green menu **Uninstall and restore original state**, or the uninstall update. Then reboot |
| The centre screen stays black after a reboot | See "Safety and recovery" in the [Install guide](Install-Guide.md). This is what the toolbox's SSH service is for |

Always save logs **before** rebooting; they are lost at reboot. Read them
before posting them publicly, as the system log can contain phone names and
Bluetooth addresses.

## Where to go next

- [Install guide](Install-Guide.md): the detailed reference, settings and recovery.
- [Supported units](Supported-Units.md) and the [support matrix](Firmware-Support-Matrix.md).
- Prefer simple turn arrows to the map? Green menu `AAClusterMap` > **Switch
  to turn-by-turn arrows instead**.
