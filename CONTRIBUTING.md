# Contributing

## Where the project stands

This started as one owner wanting the phone's map on the cockpit of one Golf.
That car works, and has for a while. Since then it has grown to VW, SEAT,
Skoda and Audi units across several firmware versions, almost entirely
through owners sending logs and photos from their own cars. Thank you, every
one of you.

It is still maintained, but more slowly: one person, with a day job, a few
times a week rather than every day. Releases come when something new has been
confirmed on a car, not daily. What would help most now is **contributors who
change the code directly**: people who port their own firmware, fix what they
find, and send pull requests. If that could be you, the rest of this page is
for you.

## Ways to help

| You have | You can |
|---|---|
| A car where it works | Test new releases, and answer questions from owners of the same make in the issues |
| A car that is not supported yet | Port it yourself: see [Port your own car](#port-your-own-car) below |
| A bug or an idea | Open an issue with your car, firmware train, what you did, what you saw, `update_result.txt` and the `run_logs` folder; or better, a pull request |
| Time and curiosity | Pick something from the open issues (CarPlay zoom from the steering wheel, turn arrows for CarPlay, the hardware decoder) |

Write in any language you like. Logs and photos need no translation.

## Use an AI assistant

Much of this project was written and debugged with an AI coding assistant:
reading disassembly, comparing logs, writing installer scripts. You don't need
to be a reverse engineer to port a firmware. You need patience, your unit's
files and a good assistant. Give it this repository, your `porting_*` folder
and `docs/Development.md`, and ask it to work through the steps below with
you. Check what it tells you against the logs: the hook's own checks are
there for exactly that.

## Forks and pull requests

Work in your own fork. When something works on your car, open a pull request
against `main`:

- **One topic per pull request** (a firmware profile, a fix, a doc change).
- **Say what car it ran on:** make, firmware train, what you tested (map up,
  route started, phone unplugged and replugged), and paste the relevant log
  lines.
- **No firmware files:** `gal`, `libautoreceiver*.so`, `libairplay.so`,
  `lsd.jxe` and the like are Volkswagen/Harman binaries. Never commit or
  attach them; share them privately if someone needs to look.
- **Keep the style:** the shell scripts run on QNX's `ksh` and must work
  without `printf`, `cmp` or `tr`; comments explain *why*, with the issue
  number that showed it.

Build with `./build_local.sh` (Docker, the QNX 6.5 toolchain image; start
Docker first). The release zip lands in `dist/`.

## Port your own car

A port is a set of numbers, a "profile", that tells the hook where things
are in your unit's Android Auto program (`gal`). Most units of the same
generation share the rest. The whole port is usually one line in
`gal_dualscreen.conf`, tried without rebuilding anything.

### 1. Collect your unit's files

Put a release on the SD card, move `COLLECT.txt` from the folder
`to only check compatibility, move this file up one folder` up into
`ClusterMap`, and run the update. Nothing is installed. The card then holds
`ClusterMap/porting_<your train>/` with `gal`, the Android Auto receiver
library, `info.txt` and the display manager's tables. These files stay with
you; don't post them.

### 2. Check the receiver library

The receiver is `libautoreceiver.so` (MIB2.5) or `libautoreceiver_qnx.so.1`
(older MIB2 High, VWG11 and Audi AUG22). Compare its SHA-256 with the two the
hook knows:

| Receiver | SHA-256 starts | Units |
|---|---|---|
| `libautoreceiver.so`, 1,067,402 bytes | `b04cb5cf` | VW P4521 and every working VWG13/SEG11/SKG13 unit so far |
| `libautoreceiver_qnx.so.1` | `c4b06d69` | VW K3342, Audi K3346 |

Identical means every offset the hook uses is already verified. Different
means step 4 has more to check (the table in `docs/Development.md`, "Adding
a firmware").

### 3. Let the tool propose a profile

```sh
pip install capstone
python3 tools/find_profile.py porting_X/gal porting_X/libautoreceiver.so MHI2_ER_XXXXX_Pxxxx
```

It prints the fingerprint addresses, the handler constructor it found, and a
ready `GAL_PROFILE_TRIAL=` line. It stops when something is missing or when
it finds more or fewer than one candidate.

**If it finds no constructor** (an older `gal`, as on S2125): find the GOT
slot that holds the address of `_ZTVN3gal25CVideoSinkCallbackHandlerE`. The
functions that load from that slot are the two destructors and the
constructor; the constructor is the one that is not a destructor. Its call
site gives the size passed to `operator new` and the arguments.
`tools/armre.py <file> dis <symbol-or-0xaddress>` disassembles any function.
This is where an AI assistant earns its keep.

### 4. Check what the tool cannot

`docs/Development.md`, section "Adding a firmware", lists every field and how
to confirm it in the disassembly. Also read `info.txt`:
- `dmdt gd` should list the cockpit map window `33` and its size;
- the context it sits in should be listed (70 on VW/SEAT/Skoda, 72 on Audi A4).

Different values go in `gal_dualscreen.conf` (`GAL_PLAYER_WINDOW`,
`GAL_VC_CONTEXT`).

### 5. Try it on the car

Add the line to `ClusterMap/gal_dualscreen.conf`, install, reboot, put the
cockpit in map view, connect the phone and start Google Maps. The hook
checks the profile against the running `gal` before using it, and leaves
Android Auto stock if it does not match.

In the logs (green menu > ClusterMap > **Save logs to SD**, before
rebooting), look for:

```text
firmware.trial result=selected
firmware.verify result=success
secondary.register result=success
render: first frame drawn                (stream-player.log)
cluster switched to the player           (stream-player.log)
```

Then start a route. If the cockpit replaces the map with "navigation active
on the mobile device", the unit needs NavActiveIgnore
(`CLUSTERMAP_ADD_NAVIGNORE=1`). It edits the script that starts the centre
screen, so check SSH works first. On the older VWG11 generation it has
broken Android Auto, so it is never added there (see #28, #39).

If anything goes wrong: green menu > ClusterMap > **Uninstall and restore
original state**, or move `UNINSTALL.txt` up one folder and run the update
again.

### 6. Send it back

Once it has survived a drive, open a pull request that adds your profile to
`k_profiles[]` in `src/firmware_profiles.h` and your train to
`SUPPORTED_TRAINS` in `greenmenu/GEM/common.sh`. Include the tool output
and the log lines above. Your car then works out of the box for the next
owner with the same firmware, and the list of working cars in the README
grows by one.

## The CarPlay side

The CarPlay map uses [harman-f's open hook](https://github.com/harman-f/mhi2_altscreen_carplay)
(`thirdparty/mhi2_altscreen_carplay/`, GPL-3.0); see `docs/CarPlay.md`. A
different `libairplay.so` can be tried with `CLUSTERMAP_CARPLAY_TRIAL`; the
hook checks every function it patches. [luka-dev's MHI2Q project](https://github.com/luka-dev/mib2q-carplay-rgi)
has solved several things this project has not yet (steering-wheel zoom,
turn arrows in the dials) and is the best reference for them.
