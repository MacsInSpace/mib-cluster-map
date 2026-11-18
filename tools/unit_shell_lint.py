#!/usr/bin/env python3
"""Shapes that behave differently in the head unit's shell (PD KSH v5.2.14).

Every rule here was measured in that shell (tests/unit_sim, docs/Unit-shell.md)
against dash and ksh93, where the same script passes. They cannot be seen on a
Mac or in CI, so they are refused when the package is built.

    unit_shell_lint.py <file or folder> ...

E1  a block that ends in "A && B": when A is false the block returns 1 and
    the unit's shell stops a "set -e" script there. Blocks: if/elif/else,
    case arm, for/while body, { }. Write "if A; then B; fi", or "A && B || :".
E2  "! cmd" as a statement: stops a set -e script when cmd succeeds.
E3  "$@" or "$*" with no arguments is an error under "set -u".
    Write ${1+"$@"}.
E4  syntax the unit's shell does not have.
E5  echo with a backslash sequence: the unit's echo expands \\n \\t \\c \\\\,
    ksh93's does not.
E6  ". file || ...": a missing file ends the script anyway.
E7  mkdir under /tmp: on the unit /tmp is /dev/shmem, files only.
"""
import pathlib
import re
import sys

OPENERS = ("then", "do", "else")
CONDS = ("if", "elif", "while", "until")
CLOSERS = ("fi", "else", "elif", "done", "esac")


def neutral(text):
    """Script text with comments, quoted text, substitutions and here-document
    bodies replaced by Q, and continued lines joined. Line count is kept."""
    out, i, n = [], 0, len(text)
    heredocs = []

    def skip_sub(j, close):
        depth = 1
        while j < n and depth:
            c = text[j]
            if c == "\\":
                j += 2
                continue
            if close == ")" and c == "(":
                depth += 1
            elif c == close:
                depth -= 1
            elif c == "'" and close == ")":
                j = text.find("'", j + 1)
                if j < 0:
                    return n
            j += 1
        return j

    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            out.append(" " if text[i + 1] == "\n" else "Q")
            if text[i + 1] == "\n":
                out.append("\x01")          # joined line: keep the count
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            out.append("Q" + "\x01" * text.count("\n", i, j))
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append("Q" + "\x01" * text.count("\n", i, j))
            i = j + 1
        elif c == "`":
            j = skip_sub(i + 1, "`")
            out.append("Q" + "\x01" * text.count("\n", i, j))
            i = j
        elif c == "$" and text[i + 1:i + 2] == "(":
            j = skip_sub(i + 2, ")")
            out.append("Q" + "\x01" * text.count("\n", i, j))
            i = j
        elif c == "$" and text[i + 1:i + 2] == "{":
            j = text.find("}", i)
            j = n if j < 0 else j
            out.append("Q")
            i = j + 1
        elif c == "(" and re.search(r"(^|[;&|\n]|\bthen|\bdo|\belse)\s*$", "".join(out[-12:])):
            j = skip_sub(i + 1, ")")
            out.append("Q" + "\x01" * text.count("\n", i, j))
            i = j
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n;"):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c == "<" and text[i + 1:i + 2] == "<" and text[i + 2:i + 3] != "<":
            m = re.match(r"<<-?\s*['\"]?(\w+)['\"]?", text[i:])
            if m:
                heredocs.append(m.group(1))
                out.append("Q")
                i += m.end()
            else:
                out.append(c)
                i += 1
        elif c == "\n" and heredocs:
            out.append("\n")
            i += 1
            while heredocs:
                word = heredocs.pop(0)
                while i < n:
                    j = text.find("\n", i)
                    j = n if j < 0 else j
                    line = text[i:j]
                    i = j + 1
                    out.append("\x01")
                    if line.strip() == word:
                        break
        else:
            out.append(c)
            i += 1
    return "".join(out)


def statements(text):
    """(line, statement) in order; ';;' is its own statement."""
    s = neutral(text)
    line, buf, start = 1, "", 1
    i, n = 0, len(s)
    while i <= n:
        c = s[i] if i < n else "\n"
        if c == "\x01":
            line += 1
        elif c == "\n" or c == ";":
            two = s[i:i + 2] == ";;"
            joined = c == "\n" and re.search(r"(&&|\|\||\|)\s*$", buf)
            if not joined:
                if buf.strip():
                    yield start, buf.strip()
                if two:
                    yield line, ";;"
                    i += 1
                buf = ""
            if c == "\n":
                line += 1
        else:
            if not buf.strip():
                start = line
            buf += c
        i += 1


def and_list(stmt):
    """True when the statement's status is that of a failed && test."""
    if "&&" not in stmt:
        return False
    return "||" not in stmt.rsplit("&&", 1)[1] and "||" not in stmt.split("&&", 1)[0]


def lint(path):
    text = path.read_text(errors="replace")
    problems = []
    if "unit_shell_lint: skip" in text[:300]:
        return []
    errexit = bool(re.search(r"^\s*set -[a-z]*e", text, re.M))
    nounset = bool(re.search(r"^\s*set -[a-z]*u", text, re.M))
    braces = []          # 'f' function body, 'g' group, 'a' group that ends an && list
    case_depth = 0
    last = None          # (line, text) of the last statement when it is an && list
    pending_func = False
    for n, stmt in statements(text):
        if stmt == ";;":
            if last:
                problems.append((last[0], "E1", "case arm ends in an && list", last[1]))
            last = None
            continue
        words = stmt.split()
        head = words[0]
        if head in CLOSERS or head == "}":
            closes_group = True
            if head == "}":
                kind = braces.pop() if braces else "f"
                closes_group = kind != "f"
                rest = stmt[1:].strip()
                if last and closes_group:
                    problems.append((last[0], "E1", "{ } ends in an && list", last[1]))
                last = (n, stmt) if kind == "a" and "||" not in rest else None
                continue
            if last:
                problems.append((last[0], "E1", "block ends in an && list before '%s'" % head, last[1]))
            last = None
            if head == "esac":
                case_depth = max(0, case_depth - 1)
                stmt = stmt[4:].strip()
            elif head == "else":
                stmt = stmt[4:].strip()
            elif head == "elif":
                stmt = ""
            else:
                stmt = stmt[len(head):].strip()
            if not stmt:
                continue
            words = stmt.split()
            head = words[0]
        # strip leading keywords and a case pattern
        cond = False
        while True:
            m = re.match(r"^(then|do|else)\b\s*", stmt)
            if m:
                stmt = stmt[m.end():]
                continue
            m = re.match(r"^(if|elif|while|until)\b\s*", stmt)
            if m:
                cond = True
                stmt = stmt[m.end():]
                continue
            break
        if not stmt:
            last = None
            continue
        if re.match(r"^case\b", stmt):
            case_depth += 1
            m = re.search(r"\bin\b\s*(.*)$", stmt)
            stmt = m.group(1) if m else ""
        if case_depth and stmt:
            m = re.match(r"^\(?[^()&;]*\)\s*(.*)$", stmt)
            if m and not re.match(r"^\w+\s*\(\)", stmt):
                stmt = m.group(1)
        if not stmt:
            last = None
            continue
        if re.match(r"^(function\s+\w+|\w+\s*\(\))\s*\{?\s*$", stmt):
            if stmt.rstrip().endswith("{"):
                braces.append("f")
            else:
                pending_func = True
            last = None
            continue
        m = re.match(r"^(function\s+\w+|\w+\s*\(\))\s*\{\s*(.*)$", stmt)
        if m:
            braces.append("f")
            stmt = m.group(2)
        if stmt.startswith("{"):
            braces.append("f" if pending_func else "g")
            pending_func = False
            stmt = stmt[1:].strip()
        elif re.search(r"(&&|\|\|)\s*\{\s*", stmt):
            m = re.search(r"(&&|\|\|)\s*\{\s*(.*)$", stmt)
            pre = stmt[:m.start()]
            braces.append("a" if m.group(1) == "&&" and "||" not in pre else "g")
            stmt = m.group(2)
        if not stmt:
            last = None
            continue
        if cond:
            last = None
        else:
            last = (n, stmt) if and_list(stmt) else None
            if errexit and re.match(r"^!\s", stmt) and "&&" not in stmt and "||" not in stmt:
                problems.append((n, "E2", "'! cmd' as a statement stops a set -e script when cmd succeeds", stmt))
    raw_lines = text.split("\n")
    for n, raw in enumerate(raw_lines, 1):
        if raw.lstrip().startswith("#"):
            continue
        if nounset and re.search(r'(?<!\+)"\$[@*]"|(?<![{+"\w])\$[@*](?!\w)', raw) and '${1+"$@"}' not in raw:
            problems.append((n, "E3", '"$@"/"$*" with no arguments fails under set -u; write ${1+"$@"}', raw.strip()))
        for pat, why in ((r"\$\{\w+/[^}]*\}", "${var/a/b}"), (r"\$\{\w+:\d+(:\d+)?\}", "${var:n:m}"),
                         (r"<<<", "<<< here-string"), (r"\$'", "$'...'"), (r"pipefail", "set -o pipefail"),
                         (r"\[\[:\w+:\]\][^'\"]*\)", "[[:class:]] in a case pattern"),
                         (r"&>", "&> redirect"), (r"\$\(\s*case\b[^()]*\bin\s+[^(\s][^()]*\)", "$(case x in a) ...) needs (a)")):
            if re.search(pat, raw) and not re.search(r"\b(sed|grep|awk|expr)\b.*" + pat, raw):
                problems.append((n, "E4", "the unit's shell has no %s" % why, raw.strip()))
        if re.search(r"\bmkdir\b[^;|&]*(/tmp/|/dev/shmem/)", raw):
            problems.append((n, "E7", "/tmp on the unit is shared memory and holds no folders: mkdir there fails", raw.strip()))
        if re.search(r"(?:^|[;&(]|\bthen\b|\bdo\b|\belse\b)\s*\.\s+\S+[^|]*\|\|", raw):
            problems.append((n, "E6", "'. file || ...' does not catch a missing file: the script ends; test [ -r file ] first", raw.strip()))
        m = re.search(r"(?:^|[;&|(]|\bthen\b|\bdo\b|\belse\b)\s*echo\s+(.*)$", raw)
        if m and re.search(r"\\[ntcbafv0\\]", re.sub(r"\$\w+|\$\{[^}]*\}", "", m.group(1).split("|")[0])):
            problems.append((n, "E5", "echo expands this backslash sequence on the unit", raw.strip()))
    return [(path, n, code, why, src) for n, code, why, src in problems]


def main(argv):
    found = []
    for root in argv:
        p = pathlib.Path(root)
        files = sorted(p.rglob("*.sh")) if p.is_dir() else [p]
        for f in files:
            found.extend(lint(f))
    for path, n, code, why, src in found:
        print(f"{path}:{n}: {code} {why}\n      {src[:140]}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
