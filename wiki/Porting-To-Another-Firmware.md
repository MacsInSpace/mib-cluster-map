# Porting to another firmware

For Harman MIB2 High and MIB2.5 High units (`MHI2_...`). Everything
firmware-specific in the hook is one entry in `src/firmware_profiles.h`.

Two people are usually involved: an **owner** with the car, and a **porter**
who can read ARM disassembly. They can be the same person.

## 1. Owner: collect the files

1. Put the release package on an SD card and add the green menu screen
   ([Install guide](Install-Guide.md)). Do not run Install.
2. Run **Status and compatibility check**, then **Collect files for porting**.
3. Open an issue with the firmware train, the car, and the contents of
   `info.txt` from the `porting_<train>` folder.

**Do not attach `gal`, `libautoreceiver.so` or `lsd.jxe`.** They are
Volkswagen/Harman firmware. `lsd.jxe` is only needed for a turn-arrows port. Get them to the porter privately.

## 2. Porter: propose a profile

```sh
pip install capstone
python3 tools/find_profile.py porting_X/gal porting_X/libautoreceiver.so MHI2_ER_XXXXX_Pxxxx
```

The tool prints the three fingerprint addresses (exact), the constructor it
found with its call site (a proposal), a comparison of the receiver library
with P4521, and a ready-made table entry and `GAL_PROFILE_TRIAL` line.

It stops, without a proposal, if the program is not a fixed-address executable,
if a fingerprint symbol is missing, or if it finds no single call site. Those
builds need the constructor found by hand, or are a different design.

## 3. Porter: check the proposed profile

The tool cannot see everything. Check each of these in the disassembly
(`tools/armre.py <file> dis <symbol-or-0xaddress>`):

| Field | What to confirm |
|---|---|
| `ctor`, `handler_size` | The call site is `operator new(size)` followed by the constructor, and the constructor stores vtable pointers into the new object. On P4521 it writes five, all inside `_ZTVN3gal25CVideoSinkCallbackHandlerE` |
| `ctl_config_off`, `ctl_creator_off` | The second and fourth arguments at that call site are `controller + offset`. The first is the configuration source, the second the renderer-creator shared pointer |
| `h_cfg_count_off`, `h_cfg_data_off`, `cfg_entry_size` | In the constructor (or the function that fills the table), the handler stores an entry count and a pointer to an array of fixed-size entries whose first two words are the resolution enum and the frame rate. **Not derived by the tool** |
| `settings_first`, `settings_last`, `stock_displayable` | The constructor copies a block of renderer settings into the handler; the stock main-screen window id (59 on VW) may appear in it. **Not derived by the tool** |
| Receiver library | If it is not byte-identical to P4521's, re-check every row of [Receiver layout verification](Receiver-Layout-Verification.md) against the new file |

Then compare the cluster display values in `info.txt`:

| Value | P4521 | Where it is set |
|---|---|---|
| Stock cluster map window | 33 ("window 33 performed 1st swap") | `GAL_VC_RESTORE_DISPLAYABLE_ID` |
| Display manager context | 70 | `GAL_VC_CONTEXT` |
| Cluster display id | 4 | `GAL_VC_DISPLAY` |

**Known gap:** `stream-player` currently issues its display commands with
those three values fixed (`dc 70 3`, `sc 4 70`, `dc 70 33`). A firmware or
brand with different values needs the player changed to read them from the
settings file. This has not been needed yet.

## 4. Owner: try it without a rebuild

Add the tool's `GAL_PROFILE_TRIAL=...` line to `AAClusterMap/gal_dualscreen.conf`
and install over SSH with `enable_hook.sh --debug`. The green menu installer
will refuse unknown firmware; that is deliberate.

A trial profile is used only when no built-in profile matches, and only if its
three fingerprint addresses equal what the unit's program really exports, so it
cannot be applied to the wrong build. Before every use the hook also compares
the first instruction at the constructor address with the profile, and does
nothing on a mismatch.

What to look for in the log (`collect_logs.sh`):

| Log line | Meaning |
|---|---|
| `firmware.verify result=failed reason=no_profile fingerprint=...` | No profile matched. The fingerprint is printed for you |
| `firmware.trial result=selected` | The trial profile is in use |
| `firmware.verify result=failed reason=profile_check check=...` | A field failed its sanity check; nothing was done |
| `secondary.video_config result=success` | The configuration table offsets are right |
| `secondary.register result=success` | The second display was built and registered |
| `aap.frame.framing ... annex_b=yes` | Video is arriving from the phone |

If Android Auto stops working, run the uninstall and reboot. A wrong profile
can crash the Android Auto program, which the unit restarts; it does not touch
anything outside it.

## 5. Make it permanent

Add the entry to `k_profiles[]` with `car_tested = 0`, open a pull request
with the evidence (tool output and log lines), and add the firmware to
`gem/common.sh` and the [support matrix](Firmware-Support-Matrix.md). It moves
to `car_tested = 1` and "Supported" once the owner has driven with it.
