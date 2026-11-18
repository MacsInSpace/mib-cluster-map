# Testing without a car

A trip to a car is the most expensive test there is. These are run first, in
this order, and a card goes to a car only when all of them pass.

| Step | Command | Time | Catches |
|---|---|---|---|
| 1 | `./build_local.sh package` | seconds | missing commands, shell shapes the unit treats differently, baked-in paths, old faults (all refuse the card) |
| 2 | `./build_local.sh simtest` | about 10 min | the install, reinstall, uninstall and every green menu script, in the unit's shell, on every train we hold files for |
| 3 | one car | a trip | what only hardware shows: picture, timing, the cockpit |

Step 1 runs `tools/check_scripts.py`, `tools/unit_shell_lint.py` (rules in
docs/Unit-shell.md), `tests/regression_guards.sh` and the unit tests.

## The simulator (`tests/unit_sim`)

A container whose only shell is the unit's shell version (pdksh 5.2.14, built
from source) with `printf tr cmp diff cut sort seq stat readlink mktemp`
removed. `make_unit.sh` lays out a unit's folders from one real unit's files
and puts logging stand-ins in place of `mount`, `sync`, `slay`, `pidin`,
`on`, `jsonlint` and `dmdt`. `scenarios.sh` then drives the card through
`final/update_run.sh`, as a software update does:

1. **collect only**: nothing on the unit may change;
2. **install**: must end in `CLUSTERMAP_INSTALL_OK`, autorun switched off;
3. **reinstall over damaged files**: every file the install added is damaged,
   and the next install must put each one back (a loaded jar was once never
   refreshed);
4. **install again**: must change nothing;
5. **uninstall**: every original file must be byte-for-byte as before;
6. **install after uninstall**;
7. **every green menu script**, with its exit code recorded in
   `build/unit_sim/codes.txt`;
8. on a train that is not supported: a clear "NOT SUPPORTED" and an untouched
   unit.

Each is run per train, per cockpit window size that make is known with, with
the window listed by the display manager and not listed, and with default
settings and with arrows, hardware decoder and sharper map on. Any message
from the shell itself (`script[12]: …`, "parameter not set", "not found")
fails the run.

```sh
./build_local.sh simtest                                  # everything
tests/unit_sim/run.sh dist/sdcard MHI2_ER_VWG13_P4521_2   # one train
UNIT_SIM_WINDOWS=none UNIT_SIM_EDITS=default tests/unit_sim/run.sh dist/sdcard
```

Results: `build/unit_sim/summary.txt`, and per run a folder with the
`update_result.txt` of each step.

### Unit files

The simulator needs each train's `gal`, `lsd.sh` and
`smartphone_integrator.json`. They are firmware files and are not in this
repository. They come from the "to only check compatibility" collection a
card writes (`porting_<train>`):

```sh
tests/unit_sim/add_unit.sh path/to/porting_MHI2_ER_SEG11_P4709
```

They are kept in `../unit_sim_units` (or `$UNIT_SIM_UNITS`). The
`smartphone_integrator.json` must be the unit's original, not one collected
after an install; the card's `backups/smartphone_integrator.json.original`
is. Without unit files the test says so and is skipped.

### What it does not prove

- QNX's own `sed`, `grep`, `awk`: the container has GNU tools. Save logs
  records what a unit really does (`tool_probe.txt`), and
  `tests/unit_sim/probe_compare.sh` lists every difference from the
  simulator (docs/Unit-shell.md), so this gap closes one car at a time.
- Anything the hook or the player does: no program of the package runs,
  only its scripts.
- Mount timing, a read-only card, a full partition.
- Trains we hold no files for.

So a pass means: the scripts run to the end in the unit's shell, on these
trains' real files, and leave the unit as intended. The car test is still
needed for the picture.

## Before a card goes to a car

- [ ] `./build_local.sh` built it, from a clean tree, and steps 1 and 2 pass.
- [ ] The card holds one package, and its `package_version.txt` is the build
      just made.
- [ ] After the car: read `update_result.txt` **before** judging what the car
      did. A failed install leaves the previous build running.

### Docker images on a Mac with several accounts

Docker Desktop keeps images per account, so `tools/docker_image.sh` keeps a
copy of each image (the simulator `mib-unit-sim`, the QNX toolchain) as a
`.tar.gz` in `../docker-images` next to the repo, or `$MIB_IMAGE_CACHE`. The
first run on an account that has the image saves it there; an account without
it loads it from there in seconds instead of building. When a Dockerfile
changes, change the image's tag in the scripts, so no account loads an old one.
Only one account's Docker Desktop should run at a time.
