# Which cars and head units are supported

Short answer: **one firmware on one head unit.** Harman MIB2.5 High
("Discover Pro", 9.2 inch glass screen) running firmware train
`MHI2_ER_VWG13_P4521`, software number 1367, with a digital cluster and Android
Auto over USB.

## Why it is so narrow

The project works by loading a small library into the head unit's own Android
Auto program. That library uses the positions of functions and data inside that
program, and those positions change with every firmware build. A build it does
not recognise is detected when it loads, and Android Auto is then left exactly
as stock. So the wrong firmware does no harm, but it also does nothing.

## By head unit generation

| Head unit | Supported | Notes |
|---|---|---|
| MIB1 | No | Different hardware and software; no Android Auto |
| MIB2 Standard (Composition Media, Discover Media; Technisat/Preh, firmware `MST2_...`) | No | Different manufacturer, processor and software from the Harman units. Nothing here applies |
| MIB2 High (Discover Pro 8 inch, Harman, firmware `MHI2_..._VWG11_...`) | No | Same family as the supported unit. A port may be possible but nobody has done or tested it |
| **MIB2.5 High (Discover Pro 9.2 inch, Harman, firmware `MHI2_ER_VWG13_...`)** | **One firmware, see below** | |
| MIB3 | Not applicable | A different platform |

## By firmware on MIB2.5 High

| Firmware train | Software number | State |
|---|---|---|
| `MHI2_ER_VWG13_P4521` | 1367 | **Supported.** Tested on a car |
| `MHI2_ER_VWG13_K4525` | 1367 | **Unknown.** Shares the software number with P4521 but is a different build. The installer checks it; see below |
| Any other `MHI2_ER_VWG13_...` train | other | Not supported |
| North American trains (`MHI2_US_...`) | | Not supported |

**"Software: 1367" on the System information screen is not enough to be sure**,
because two firmware trains carry that number. To see the train:

- green menu, `MQBCoding` > `Customization` > `AAClusterMap` > **Status and
  compatibility check**, which prints the train and a verdict; or
- the folder name the toolbox creates under `Backup/` on its SD card.

On a train other than P4521, the status check compares the sizes of the two
Android Auto program files with the tested ones. If they differ, the installer
refuses. If they match, it installs and says the firmware is untested; the
library then does its own exact check when Android Auto starts. If you try this
on K4525, please report the result either way.

## By brand

| Brand | Supported | Notes |
|---|---|---|
| Volkswagen | Yes, on the firmware above | Developed on a Golf 7.5. Other models with the same unit and firmware should behave the same but are untested |
| Skoda, SEAT | No | Their firmware trains (`..._SKG13_...`, `..._SEG11_...`) are different builds |
| Audi with MIB2 High (`MHI2Q_...`) | No | Different processor. See [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay), which does Android Auto and CarPlay on those units |

## Other requirements

| Requirement | Notes |
|---|---|
| Digital cluster (Active Info Display) | The cluster must be able to show the navigation map. Analogue dials with a small centre display cannot |
| Android Auto over USB | Wireless Android Auto adapters are untested |
| [MQB Coding MIB2 Toolbox](https://github.com/jilleb/mib2-toolbox) | Needed to get onto the unit at all, and for its NavActiveIgnore patch |
| Android Auto already activated on the unit | This project does not unlock Android Auto |

## Frequently asked

**Does it do CarPlay?** No. For CarPlay maps on VW and Skoda clusters see
[omonob/MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps).

**Can I update my unit to the supported firmware?** Firmware updates are
outside this project. Updating a head unit carries its own risks, including
losing activated features. Research it for your exact unit first.

**Will it be ported to my firmware?** Only if someone with that firmware does
the work. [Receiver layout verification](Receiver-Layout-Verification.md)
describes the method, and the fixed addresses to re-derive are at the top of
`src/video_sink_hook.c`.

**Does the navigation built into the car still work?** Yes. The cluster shows
the phone's map only while Android Auto is sending it.

**Can I zoom the cluster map?** No. See
[Cluster map zoom](Cluster-Zoom-Findings.md).
