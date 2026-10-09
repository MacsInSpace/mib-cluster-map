# Quick start: from a blank SD card to the map on your cluster

A step-by-step walkthrough for someone who has not modified a head unit
before. It takes about 30 to 45 minutes. Read it through once before starting.

> [!CAUTION]
> You are changing system files on your car's head unit. Do it parked, with the
> engine running or a battery charger connected, and never switch the ignition
> off while something is installing. If any step does not look like the
> description, stop and ask before continuing.

## What you need

- A car with the **Discover Pro 9.2 inch** head unit and a **digital cluster**.
- An **SD card**, 2 GB to 32 GB. Cards larger than 32 GB are awkward to format
  correctly, so avoid them.
- A computer with an SD card reader.
- An **Android phone** and a USB cable that already works with Android Auto in
  this car.
- About 30 minutes when you can stay parked.

## Step 1: check your head unit

On the head unit: `MENU` > `Setup` > `System information`.

You need **Software: 1367**. If it shows anything else, this release does not
support your unit yet; see the [support matrix](Firmware-Support-Matrix.md).

"1367" is necessary but does not prove the firmware is the right one. Step 6
does the real check, before anything is changed.

## Step 2: prepare the SD card

The card needs two things on it: the **MQB Coding MIB2 Toolbox**, which gives
you the menu this project plugs into, and **this project's package**.

1. **Format the card as FAT32.** This erases it.
   - Windows: right-click the card in File Explorer > `Format` > File system
     `FAT32` > `Start`.
   - macOS: Disk Utility > select the card (the device, not the volume) >
     `Erase` > Format `MS-DOS (FAT)`, Scheme `Master Boot Record`.
2. **Add the toolbox.** Go to
   [github.com/jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox),
   click `Code` > `Download ZIP`, and extract it. Copy what is **inside** the
   extracted folder to the card, so that `Toolbox`, `Custom` and
   `metainfo2.txt` sit at the top level of the card.
3. **Add this project.** Download the zip from this repository's
   [Releases](../../../releases) page and extract it. Copy the `AAClusterMap`
   folder to the top level of the card. Copy the `Custom` folder too; when
   asked, choose to **merge** it with the one already there. It adds one file
   and replaces nothing.

The card should now look like this:

```text
(SD card)
├── AAClusterMap/                       this project
├── Custom/
│   └── GreenMenu/
│       └── aa-cluster-map.esd          this project's menu screen
├── Toolbox/                            the toolbox
├── metainfo2.txt                       the toolbox
└── ... the toolbox's other folders and files
```

4. Eject the card properly, and put it in **SD slot 1** of the head unit. Make
   sure the other SD slot is **empty**.

## Step 3: install the toolbox on the head unit

Skip this step if the toolbox is already installed (you have an `mqbcoding`
entry in the green menu; see step 4).

These steps are the toolbox's own, from its README. If your screen differs,
follow the toolbox's instructions.

1. Hold the **MENU** button until the service screen appears. It takes several
   seconds.
2. Choose `Software updates/versions`, then `Update` in the top right corner.
3. Choose the SD card, then `MQB Coding MIB2 Toolbox`.
4. Let the update run. The unit restarts several times. It then shows a list
   of modules, most marked `N/A`; the `Toolbox` line should say `Y`. Press the
   back button in the top right.
5. It asks you to connect a computer and clear error codes. That is not
   needed: press `Cancel`.
6. The unit restarts once more and returns to the normal home screen.

## Step 4: open the green menu

The "green menu" is the unit's hidden engineering menu. The toolbox adds its
own section to it.

1. Hold the **MENU** button until the service screen appears.
2. Choose `Testmode`. On older software, keep holding MENU for about ten
   seconds to reach the developer menu.
3. Choose `Green Developer Menu`. The screen turns green with white text.
4. You should see an entry called **`mqbcoding`**. Open it.

To leave the green menu, press the unit's `MENU` or `HOME` button.

Everything in this menu is powerful. Do not change entries this guide does not
mention.

## Step 5: two toolbox patches to apply first

Both are in the toolbox, under `mqbcoding` > `Customization`.

1. **Required.** `Navigation` > **Ignore navigation-active status from
   smartphone**. Without it the cluster hides its map whenever the phone is
   navigating. If your unit already has it, running it again is harmless.
2. **Strongly recommended.** `Advanced` > **Install SSHD service**. This is
   your way back into the unit from a laptop if the screen ever fails to
   start. It needs a little preparation, described in the toolbox's
   [SSH login guide](https://github.com/jilleb/mib2-toolbox/wiki/SSH-Login).
   You will not use it during a normal install.

Reboot the unit afterwards: hold the **power button for ten seconds** until
the screen goes off and the VW logo appears.

## Step 6: add this project's screen and check compatibility

1. Open the green menu again (step 4) and go to
   `mqbcoding` > `Customization` > `GreenMenu`.
2. Run **Install GreenMenu screens and scripts from Custom/GreenMenu**. A
   message about a missing `scripts` folder is harmless.
3. Leave the green menu completely and open it again.
4. Go to `mqbcoding` > `Customization` > **`AAClusterMap`**.
5. Run **1. Status and compatibility check**.

Read the result:

| It says | What to do |
|---|---|
| `supported: yes (tested firmware)` | Continue to step 7 |
| `supported: yes (UNTESTED firmware ...)` | It may work, but nobody has tried your firmware. Continue only if you accept that, and please report the result |
| `supported: NO` | Stop. Nothing has been changed. Consider **Collect files for porting**; see [Supported units](Supported-Units.md) |
| `NavActiveIgnore: NOT loaded` | Go back to step 5 |

## Step 7: install

1. In the same screen, run **2. Install cluster map**.
2. Wait for **`AACLUSTER_INSTALL_OK`**. If you see `AACLUSTER_INSTALL_FAILED`
   or `NOT SUPPORTED`, stop; the messages above it say why, and nothing needs
   undoing.
3. Leave the green menu and **hold the power button for ten seconds** to
   reboot.

You can leave the SD card in or take it out. Keep it somewhere safe either
way: it holds the backups and the uninstaller.

## Step 8: use it

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
| Android Auto keeps disconnecting | Green menu > `AAClusterMap` > **Save logs to SD**, then **Uninstall and restore original state**, reboot, and open an issue |
| The map appears, then goes blank | Run the status check. If it says the turn-by-turn jar is loaded, run **2. Install cluster map** again and reboot |
| You want it gone | **Uninstall and restore original state**, then reboot |
| The centre screen stays black after a reboot | See "Safety and recovery" in the [Install guide](Install-Guide.md). This is what the SSH service from step 5 is for |

Always save logs **before** rebooting; they are lost at reboot. Read them
before posting them publicly, as the system log can contain phone names and
Bluetooth addresses.

## Where to go next

- [Install guide](Install-Guide.md): the detailed reference, settings and recovery.
- [Supported units](Supported-Units.md) and the [support matrix](Firmware-Support-Matrix.md).
- Prefer simple turn arrows to the map? `AAClusterMap` > **Switch to
  turn-by-turn arrows instead**.
