# Firmware support matrix

The goal is every Harman MIB2.5 High firmware, and the older MIB2 High where
it turns out to be close enough. One package serves all supported firmware:
the hook carries a table of profiles and picks the one that matches the unit.

A row only becomes "Supported" after it has run on a car. If your firmware is
"Wanted", you can make it happen: see
[Porting to another firmware](Porting-To-Another-Firmware.md).

## States

| State | Meaning |
|---|---|
| **Supported** | Profile in the hook, has run on a car |
| **Derived** | Profile worked out from an owner's files, not yet run on a car. Not shipped in the release |
| **Wanted** | Nobody has supplied files yet |
| **Different platform** | Not a Harman MIB2/MIB2.5 High unit; out of scope |

There are two features, and they port separately:

- **Cluster map**: the phone's map video on the cluster. Native code; needs a
  hook profile per firmware.
- **Turn arrows**: next-turn arrow, distance and track information drawn by the
  cluster itself, from [adi961/mib2-android-auto-vc](https://github.com/adi961/mib2-android-auto-vc).
  A Java patch; needs rebuilding against each firmware's Java interface.

## MIB2.5 High (Discover Pro 9.2 inch and equivalents)

| Brand | Firmware train | Software | Cluster map | Turn arrows | Notes |
|---|---|---|---|---|---|
| VW | `MHI2_ER_VWG13_P4521` | 1367 | **Supported** | Works (jar author and this project) | Golf 7.5. The development car |
| VW | `MHI2_ER_VWG13_K4525` | 1367 | Wanted | Works (jar author) | Same software number as P4521. The status check says whether its Android Auto files are identical; if so the map may already work |
| VW | `MHI2_ER_VWG13_P4512` | ? | Wanted | Reported not working | |
| Skoda | `MHI2_ER_SKG13_P4526` | 1440 | Wanted | Reported not working | Cluster routing may differ from VW |
| VW, other regions | `MHI2_US_VWG13_...` and others | ? | Wanted | Unknown | |

## MIB2 High (Discover Pro 8 inch)

| Brand | Firmware train | Software | Cluster map | Turn arrows | Notes |
|---|---|---|---|---|---|
| VW | `MHI2_ER_VWG11_K3342` | 1427 | Wanted | Reported not working | Older build of the same program family. Unknown how much differs |
| SEAT | `MHI2_ER_SEG11_P4709` | 1447 | Wanted | Requested, untested | |

"Reported not working" and "Works (jar author)" come from the jar project's own
compatibility table and issue tracker, not from testing here.

Firmware not listed is simply unknown to this project, not excluded. Software
numbers marked `?` have not been confirmed; corrections are welcome.

## Out of scope

| Unit | Why |
|---|---|
| MIB2 Standard (`MST2_...`: Composition Media, Discover Media) | Different manufacturer, processor and software |
| Audi MIB2 High (`MHI2Q_...`) | Different processor and graphics. See [kamgurgul/mib2q-carplay](https://github.com/kamgurgul/mib2q-carplay) |
| MIB1, MIB3 | Different platforms |

## What "supported" needs, per firmware

For the cluster map:

1. A profile in `src/firmware_profiles.h` for that build of the Android Auto program.
2. The same object layouts in its receiver library, or a note of what differs.
3. The cluster display values (which display, context and window carry the map).
4. The NavActiveIgnore patch working on that firmware.
5. A successful drive: map up, route started, phone unplugged and replugged.

For turn arrows on a firmware where the existing jar does not work: the jar
replaces Java classes inside the unit's interface, and those classes differ
between firmware. Someone has to rebuild the patch against that firmware's
`lsd.jxe` with the jar project's toolchain (an IBM Java 1.2-level compiler),
fixing whatever no longer matches, and test it on a car. That work belongs in
the jar's own project; this package only bundles its released jar. The menu entry **Collect for porting, with Java image** copies `lsd.jxe` as
well, for an owner who wants to attempt such a port.
