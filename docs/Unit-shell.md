# The unit's shell and commands

Everything the card runs is run by the head unit's `/bin/sh`. It is not the
shell on a Mac, on Linux or in CI, and a script that passes all three has
stopped on cars four times. This page lists the differences that were
measured, so nobody has to find them on a car again.

The unit's shell is **PD KSH v5.2.14 99/07/13.2** (QNX 6.5; `sh` and `ksh` are
the same program). Its behaviour here was measured three ways:

- **Car**: seen in an install log from a car.
- **Same shell**: measured in a build of the same pdksh 5.2.14 source
  (`tests/unit_sim`), which reports the same version string. The QNX program
  itself is a QNX build of that source; where both were run they agreed.
- Not measured: said so.

Later shells that call themselves pdksh do **not** behave the same: Debian's
`pdksh 5.2.14-25`, `mksh`, `dash`, macOS `ksh` (ksh93) and `bash` all pass the
first rule below. A bench in any of them proves nothing about it.

## Rules

Each rule is checked by `tools/unit_shell_lint.py` when a card is packed.

### 1. Never end a block with `A && B`

```sh
if [ "$FULL_FRAME" = auto ]; then
    FULL_FRAME=${CAR_FULLFRAME:-0}
    [ "$FULL_FRAME" = 1 ] && echo "on"      # stops the install when it is 0
fi
```

When `A` is false the list returns 1, the block returns 1, and under
`set -e` the unit's shell exits there, silently. Every other shell carries
on. It applies to the last command of an `if`/`elif`/`else` branch, a `case`
arm, a `for`/`while` body and a `{ }` group, including `A && { ...; }` and
including a block inside a function. (Car: beta14 #52, cpzoom1 #19,
keep-settings, v1.2.7-golf5/6. Same shell: all eight block kinds.)

Not affected: the same list at the top level of the script, in the middle of
a block, or as an `if`/`while` condition.

Write one of:

```sh
if [ "$FULL_FRAME" = 1 ]; then echo "on"; fi
[ "$FULL_FRAME" = 1 ] && echo "on" || :
```

### 2. No `! cmd` as a statement

`! grep -q x file` on a line of its own exits a `set -e` script when the
command *succeeds*. Use it only as a condition: `if ! grep -q x file; then`.
(Same shell.)

### 3. `"$@"` with no arguments is an error under `set -u`

`for a in "$@"` and `x="$*"` fail with "parameter not set" when there are no
arguments. Write `${1+"$@"}`. (Same shell.)

### 4. Syntax the shell does not have

| Not available | Use |
|---|---|
| `${var/a/b}`, `${var:0:1}` | `sed`, `expr`, `${var#pat}` `${var%pat}` |
| `$'a\tb'`, `<<<`, `&>` | a literal tab, a here-document, `> f 2>&1` |
| `set -o pipefail` | check the command that matters on its own |
| `[[:alpha:]]` in a `case` pattern | `[A-Za-z]` |
| `$(case x in a) ...;; esac)` | `(a)` with the opening bracket, or backticks |
| a `printf` builtin | `echo` (see below) |

Available, though dash lacks them: `[[ ]]`, `local`, `typeset`, `function f`,
`let`, `(( ))`, `$(< file)`, `==` in `[ ]`. Do not use them anyway: the
checks on this machine run in dash too.

### 5. `echo` expands backslashes

`echo "a\tb"` prints a tab and `echo "C:\new"` prints a line break, as in
dash; ksh93's echo prints the text as written. Never `echo` text that can
hold a backslash (a path from a setting, a `sed` expression). (Same shell.)

### 6. Other measured differences

| | Unit's shell | ksh93 (macOS) |
|---|---|---|
| a variable set in `cmd \| while read` | lost after the loop | kept |
| `echo x \| read V` | `V` stays empty | set |
| `$((010 + 1))` | 11 | 9 |
| `wc -c` output | no leading spaces on Linux; QNX not measured | padded |
| `$LINENO` in an exit trap | 0 or the trap's own line | the failing line |

So: read loops take their input from a file (`done < file`), and a number
from `wc` always goes through `sed 's/ //g'`.

### 7. What stops a `set -e` script in every shell

These are the same everywhere, but they only *happen* on a unit, where a file
is missing or a program is absent, and the installer's output hides the
message:

- `X=`cmd`` when `cmd` fails: `grep` with no match, `head` or `sed` on a
  missing file, `expr` with a result of 0. A pipeline counts by its **last**
  command, so `... | tail -1` and `... | sed ...` are safe ends, and
  `|| :` inside or after always is. (Car: `head` on a missing file.)
- a function whose last command is a false test, called on a line of its own.
- `. file || :` when `file` is missing: `.` is a special builtin and its
  failure ends the script whatever follows. Test with `[ -r file ]` first.
  (Same shell.)
- `$((0x10))`: "bad number". Hex only through `awk`.
- `wc -c < "$F"` with `$F` empty: the shell prints "cannot open" itself, past
  any `2>/dev/null`.

### 8. `/tmp` holds files, not folders

On the units `/tmp` is a link to `/dev/shmem`, QNX's shared memory. A file
can be written there; `mkdir` fails with "Function not implemented". Use
`/tmp/clustermap_<name>` files, or a folder on the card. (Car: the v1.2.7
probe on an Audi A3, a Skoda and a Golf R. Lint rule E7.) The simulator's
`/tmp` is a normal folder, so it cannot catch this.

## Commands

A unit has far fewer programs than a desktop, and trains differ.

| | |
|---|---|
| **Not on some or all units** (car) | `printf` `tr` `cmp` `diff` |
| **Treated as absent** (not on the Golf's program folders, or failed once) | `cut` `sort` `seq` `stat` `readlink` `mktemp` `xargs` `which` `od` `cksum` |
| **Used by the installer on every supported car** | `sed` `grep` `awk` `wc` `cp` `mv` `rm` `mkdir` `chmod` `mount` `expr` `head` `tail` `cat` `ls` `basename` `dirname` `sync` `touch` `find`; QNX's own `slay` `pidin` `on` |

`tools/check_scripts.py` refuses a card that uses a command from the first
two rows without testing for it (`command -v`). `GEM/install.sh` prints
"Not on this unit:" with what it found missing, in every install log.

The builds, from `tool_versions.txt` of three cars (Golf R/Passat P4512,
Skoda P4526, Audi A3 P5089; v1.2.7): the same shell everywhere (211607
bytes); **GNU sed 4.1.5**, **GNU Awk 3.1.5**, `expr`, `wc` and `find` in
`/mnt/app/armle/usr/bin` (sed in `/bin` on two of them); **QNX's own**
`grep`, `head` and `tail` (no `--version`). The simulator has GNU sed 4.2.1
and gawk 3.1.7; its grep, head and tail are GNU, so an option of those three
is not proven by it.

Option differences seen on cars:

- `grep "a\|b"` matches nothing: the unit's grep takes `\|` as text. Use two
  greps or `grep -e a -e b`.
- The QNX builds of `sed`, `grep`, `awk`, `tail` and `head` are not the GNU or
  BSD ones. The simulator runs GNU tools, so an unusual option is **not**
  proven by it. Stay with what the installer already uses: `sed -n 's/…/p'`,
  `sed -e`, `grep -q`, `grep -v`, `grep -c`, `tail -1`, `head -1`,
  `wc -c`, `awk '{ … }'`.

## Checking a unit against the simulator

Save logs runs `scripts/unit_probe.sh` on the unit: about 250 one-line
checks of the shell, `sed`, `grep`, `awk`, `expr`, `head`/`tail`, file
commands and which programs exist, each in its own child shell. It changes
nothing and takes a few seconds. Its result is `run_logs/N/tool_probe.txt`.

```sh
tests/unit_sim/probe_compare.sh run_logs/3/tool_probe.txt MHI2_ER_VWG13_P4521_2
```

runs the same file in the simulator and lists every check that differs. Each
difference is fixed in the simulator (`tests/unit_sim/Dockerfile`, e.g. a
QNX-like `sed`) or becomes a rule here and in `tools/unit_shell_lint.py`.
Car results are kept in `tests/unit_sim/probes/` (names, sizes and results
only; no firmware).

## When an install stops with no message

1. Read `update_result.txt` first; the last line printed is just before the
   stop.
2. Run the same card in the simulator (docs/Testing.md). The v1.2.7-golf6
   stop reproduced there at the same line as on the car.
3. For the exact command, run the installer with `sh -x` inside the simulator.
