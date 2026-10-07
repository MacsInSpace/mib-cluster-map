# Field guide: installing this on another car

Local notes, not from upstream. They describe the build on the `local-fixes`
branch, which uses an open toolchain and adds a few fixes. Status: the map has
reached the cluster on one car. It is not yet proven stable. Read "Known open
issues" before offering it to anyone.

## 1. Will it fit their car

All of these must be true. The hook checks the last one itself and leaves
Android Auto stock if it fails.

| Requirement | How to check |
|---|---|
| Harman MIB2.5 "Discover Pro" head unit | 9.2 inch glass screen, part number like `5NA 035 045` |
| Digital cluster (Active Info Display) | the cluster can show the VW navigation map |
| Firmware `MHI2_ER_VWG13_P4521`, software 1367 | Menu, Setup, System information shows "Software: 1367" |
| Root shell access | jilleb/mib2-toolbox installed, SSH service installed with an RSA key |
| NavActiveIgnore patch | toolbox green menu; without it the cluster drops its map when the phone navigates |

Other firmware trains are **not** supported. The hook contains fixed addresses
inside the stock `gal` program. On a mismatch its log says
`event=firmware.verify result=failed` and nothing else happens. Porting to
another train means re-deriving those addresses; see `port/re/LAYOUTS.md` in the
working folder for the method used on this unit.

## 2. Build once, reuse for every car on the same firmware

Needs Docker. On Apple Silicon the toolchain runs under emulation.

```sh
# a) the cross compiler image (about ten minutes, once)
git clone https://github.com/luka-dev/qnx65-armv7-toolchain
cd qnx65-armv7-toolchain && ./host-scripts/qnx-run.sh build 8.5
# if ftp.gnu.org refuses connections, replace it in the Dockerfile with
# https://mirrors.kernel.org/gnu/ (the checksums are pinned, so this is safe)

# b) this project
cd ../mhi2-android-auto-video-vc && ./build_local.sh
```

Result: `dist/sdcard/`. Copy its **contents** to the root of a FAT32 SD card.
The binaries are identical for every car on this firmware, so friends do not
need to build; give them the folder and its `SHA256SUMS.txt`.

## 3. Install

SD card in slot 1, laptop on the car's wifi hotspot, SSH in as root.

```sh
mount -uw /fs/sda0
sh /fs/sda0/enable_hook.sh
```

Then hold the power button for ten seconds to reboot. Keep the engine running
or a charger connected: an afternoon of ignition-on testing flattened a healthy
battery here, and low voltage produces unrelated dash warnings
("Proactive occupant protection restricted", "Manoeuvre braking restricted").

What the installer changes:

| Where | What |
|---|---|
| `/mnt/system/etc/eso/production/smartphone_integrator.json` | adds the preload entries to the `gal` child; original saved beside it as `.gal-dualscreen.original` |
| `/mnt/app/eso/lib/gal_dualscreen/` | hook library, helper library, a copy of the settings file |
| `/mnt/app/navigation/stream-player` | the video player |

## 4. Test and collect logs

1. Wait about two minutes after boot.
2. Plug the phone in, open Google Maps in Android Auto, put the cluster in map view.
3. Start a route.
4. Run `sh /fs/sda0/collect_logs.sh` and bring the card back. Logs land in `run_logs/`.

The logs are in RAM on the unit and are lost at the next reboot, so collect
before switching off.

## 5. Uninstall

```sh
mount -uw /fs/sda0
sh /fs/sda0/disable_hook.sh
```

Reboot. This restores the saved supervisor file and removes the installed files.

## 6. Settings a friend may need to change

Edit `gal_dualscreen.conf` on the SD card, then re-run `enable_hook.sh` so the
internal copy is refreshed, and reboot.

| Setting | Shipped value | Change it when |
|---|---|---|
| `GAL_SECONDARY_DPI` | 125 | map text and turn card are too big (lower) or too small (higher) |
| `GAL_SECONDARY_INSETS` and `GAL_SECONDARY_UI_CONFIG_HEX` | 40,40,127,127 | map controls are hidden behind the dials. The hex value overrides the insets, so change both or delete the hex line |
| `GAL_SECONDARY_UI_THEME` | 2 (dark) | 0 follows the phone, 1 is light |
| `GAL_DUALSCREEN_AAP_MINOR` | 7 | never, unless testing: the phone only offers the cluster display at this value |
| `GAL_FIX_SUPPRESS_UNEXPECTED` | on | never, unless reproducing the connection loop |
| `GAL_DUALSCREEN_DEBUG` | 1 | set 0 once it is stable, to cut log volume |

## 7. Known open issues

| Symptom | State |
|---|---|
| Connection loop, phone disconnects every ~17 s | Fixed. See [Navigation status messages](Navigation-Status-Messages.md) |
| Map is solid with no route, fails when a route starts | **Being confirmed.** Seen with `VCAndroidAuto.jar` loaded; the installer now removes that jar's start-up line |
| Turn arrows from `VCAndroidAuto.jar` do not update | Expected for now: the newer navigation messages are ignored, not translated |
| No steering-wheel zoom of the cluster map | The upstream author's jar for this was never published |

### The turn-by-turn jar is removed by the installer

On the test car the map was solid with no route and failed the moment a route
started, while `VCAndroidAuto.jar` was loaded. `enable_hook.sh` therefore checks
the Java start-up script and:

- warns if NavActiveIgnore is missing;
- removes the one line that loads `VCAndroidAuto.jar`, saving the previous file.

Pass `--keep-turn-by-turn` to skip the removal. `disable_hook.sh` does not put
the line back; run `sh /fs/sda0/remove_turn_by_turn_jar.sh --restore` for that.
Whether removing the jar fully cures the route-start failure is still being
confirmed.

## 8. If something goes badly wrong

- **Android Auto will not start at all:** run `disable_hook.sh` and reboot.
- **The centre screen stays black after `remove_turn_by_turn_jar.sh`:** SSH still
  works without the interface; run it again with `--restore` and reboot.
- **Never** switch the ignition off while an install script is running.
