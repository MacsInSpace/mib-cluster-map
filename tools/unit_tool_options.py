#!/usr/bin/env python3
"""Check the options the card's scripts give the unit's tools against the
tools' own help.

The unit's programs are QNX builds for ARM and cannot run here, so the
simulator runs other builds of grep, sed and the rest (docs/Unit-shell.md).
But every QNX program carries its help text (the QNX_usage section), and that
lists the options it takes. Copies taken off owners' units (green menu Save
logs > unit_bin) are kept privately, one folder per unit:

    $UNIT_SIM_UNITS/<train>/bin/list.txt      "grep /usr/bin/grep" per line
    $UNIT_SIM_UNITS/<train>/bin/usage/*.txt   help text per program

(UNIT_SIM_UNITS defaults to ../unit_sim_units next to the repo.) An option a
script uses must be in the help of every unit that has the tool. Tools whose
help lists no options (sed and awk only say "--help") are left to the tool
probe (scripts/unit_probe.sh), which runs on the car. Without any unit help
the check says so and passes, so the public repo still builds.

    python3 tools/unit_tool_options.py DIR...   (scripts under DIR, recursive)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNITS = os.environ.get("UNIT_SIM_UNITS", os.path.join(ROOT, "..", "unit_sim_units"))
# The probe tries options on purpose to find which ones a unit lacks.
SKIP_FILES = {"unit_probe.sh"}
# "head -1" / "tail -20": the old count form, not in the help but confirmed on
# the car by the probe (head_1, tail_1).
COUNT_FORM = {"head", "tail"}


def unit_options():
    """{tool: {unit: set of option letters}} from every unit's help."""
    found = {}
    if not os.path.isdir(UNITS):
        return found
    for unit in sorted(os.listdir(UNITS)):
        b = os.path.join(UNITS, unit, "bin")
        lst = os.path.join(b, "list.txt")
        if not os.path.isfile(lst):
            continue
        for line in open(lst, errors="replace"):
            parts = line.split()
            if len(parts) != 2 or not parts[1].startswith("/"):
                continue
            tool, path = parts
            help_file = os.path.join(b, "usage", path[1:].replace("/", "_") + ".txt")
            if not os.path.isfile(help_file):
                continue
            text = open(help_file, errors="replace").read()
            letters = set()
            for grp in re.findall(r"\[-([A-Za-z0-9#]+)", text):
                letters.update(grp)
            for opt in re.findall(r"(?:^|[\s|\[])-([A-Za-z0-9#])(?=[\s,|\]]|$)", text, re.M):
                letters.add(opt)
            letters.discard("-")
            if letters:
                found.setdefault(tool, {})[unit] = letters
    return found


def scripts(dirs):
    for d in dirs:
        for top, _, files in os.walk(d):
            for f in sorted(files):
                if f.endswith(".sh") and f not in SKIP_FILES:
                    yield os.path.join(top, f)


def main(argv):
    opts = unit_options()
    if not opts:
        print("unit_tool_options: no unit help under %s; skipped" % UNITS)
        return 0
    call = re.compile(r"(?:^|[\s|;&`(])(" + "|".join(map(re.escape, sorted(opts))) +
                      r")((?:[ \t]+-[A-Za-z0-9#]+)+)")
    bad = 0
    for path in scripts(argv[1:]):
        for n, line in enumerate(open(path, errors="replace"), 1):
            code = re.sub(r"(^|\s)#.*$", "", line)
            for m in call.finditer(code):
                tool = m.group(1)
                for word in m.group(2).split():
                    if tool in COUNT_FORM and re.fullmatch(r"-[0-9]+", word):
                        continue
                    for letter in word[1:]:
                        lacking = [u for u, have in opts[tool].items() if letter not in have]
                        if lacking:
                            print("%s:%d: %s -%s is not in the help of %s's %s" %
                                  (os.path.relpath(path), n, tool, letter, ", ".join(lacking), tool))
                            bad += 1
    units = sorted({u for t in opts.values() for u in t})
    print("unit_tool_options: %d tools checked against %s: %s" %
          (len(opts), ", ".join(units), "%d problem(s)" % bad if bad else "ok"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
