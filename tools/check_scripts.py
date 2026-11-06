#!/usr/bin/env python3
"""Refuse a package whose scripts use what some head units do not have.

Units differ, and each of these has failed on a car: printf and tr (#19, #28),
cmp and diff (absent from the firmware image), grep with \\| (the unit's grep
takes it as literal text). They only show up on a car, so they are stopped here.

Also a case arm that ends in "[ ... ] && cmd ;;": when the test is false the
case returns 1, and the unit's shell stops a set -e script there (beta14 #52,
cpzoom1 #19). Write "if [ ... ]; then cmd; fi ;;" instead.

    check_scripts.py <package folder>

A tool is allowed on a line that tests for it (command -v), and inside an
"if command -v TOOL" block of the same script.
"""
import pathlib
import re
import sys

TOOLS = ("printf", "tr", "cmp", "diff", "seq", "cut", "sort")
CASE_AND = re.compile(r"\)\s*\{?\s*\[[^;]*\]\s*;?\s*\}?\s*&&[^;|]*;;\s*$")
CMD = re.compile(r"(?:^|[|;&(`]|\bthen\b|\bdo\b|\belse\b)\s*(" + "|".join(TOOLS) + r")(?:\s|$)")


def code(line):
    """The line without a comment or quoted text (quotes can hold prose)."""
    out, quote = "", None
    for ch in line:
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
            continue
        if ch == "#":
            break
        out += ch
    return out


def check(path):
    problems = []
    guarded = set()
    for n, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if raw.lstrip().startswith("#"):
            continue
        for tool in re.findall(r"command -v (\w+)", raw):
            guarded.add(tool)
        if re.search(r"\bgrep\b[^|]*\\\|", raw) and not raw.lstrip().startswith("echo"):
            problems.append(f"{path}:{n}: grep with \\| does not work on the unit")
        if CASE_AND.search(code(raw)):
            problems.append(f"{path}:{n}: case arm ends in a test with &&; under set -e use if")
        for tool in CMD.findall(code(raw)):
            if tool not in guarded:
                problems.append(f"{path}:{n}: {tool} is not on every unit")
    return problems


def main():
    problems = []
    for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.sh")):
        problems += check(path)
    print("\n".join(problems) if problems else "scripts ok")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
