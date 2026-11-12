#!/usr/bin/env python3
"""Compare the code of a replacement class with the stock class it replaces.

    bytecode_diff.py <ours.jar> <stock lsd.jar> <class> [method that may differ ...]

Both are disassembled with javap -c; constant-pool numbers, offsets and the
padding jxe2jar leaves after a method's last instruction are dropped, and
branch targets become instruction numbers, so two compilations of the same
code compare equal. A method named on the command line may differ (it is
printed side by side); any other difference fails, except added private
methods. A method name matches all its overloads.
"""
import re
import subprocess
import sys
import tempfile
import zipfile

INSN = re.compile(r"^\s*(\d+): (\w+)\s*(.*)$")
BRANCH = re.compile(r"^(if\w*|goto\w*|jsr\w*)$")


def methods(jar, cls):
    with tempfile.TemporaryDirectory() as d:
        with zipfile.ZipFile(jar) as z:
            z.extract(cls + ".class", d)
        out = subprocess.run(["javap", "-c", "-p", d + "/" + cls + ".class"],
                             capture_output=True, text=True, check=True).stdout
    found, name, body = {}, None, []
    for line in out.splitlines():
        if line.startswith("  ") and not line.startswith("   ") and line.rstrip().endswith(";"):
            if name:
                found[name] = body
            name, body = re.sub(r"\s+", " ", line.strip().rstrip(";")), []
            continue
        m = INSN.match(line)
        if m and name:
            body.append((int(m.group(1)), m.group(2), m.group(3)))
        elif name and line.strip().startswith(("{", "}")) or (name and re.match(r"^\s+(default|-?\d+): \d+$", line)):
            body.append((None, "switch", line.strip()))
    if name:
        found[name] = body
    return {k: normal(v, cls) for k, v in found.items()}


def normal(body, cls):
    real = [b for b in body if b[0] is not None]
    index = {off: i for i, (off, _, _) in enumerate(real)}
    out = []
    for off, op, arg in body:
        if off is None:
            m = re.match(r"^(default|-?\d+): (\d+)$", arg)
            out.append(("case", m.group(1) + "->" + str(index.get(int(m.group(2)), "?"))) if m else ("switch", arg))
            continue
        if op == "nop":
            continue
        if op == "ldc_w":
            op = "ldc"  # the same load; only the constant pool's size differs
        # javap names the owner of a reference only when it is another class.
        comment = arg.split("//", 1)[1].strip().replace(cls + ".", "") if "//" in arg else ""
        operand = re.sub(r"#\d+(,\s*\d+)?", "", arg.split("//", 1)[0]).strip()
        if BRANCH.match(op) and operand.isdigit():
            operand = "@" + str(index[int(operand)])
        out.append((op, (operand + " " + comment).strip()))
    while out and out[-1][0] == "nop":
        out.pop()
    return out


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(2)
    ours, stock, cls = sys.argv[1], sys.argv[2], sys.argv[3]
    allowed = set(sys.argv[4:])
    a, b = methods(stock, cls), methods(ours, cls)
    bad = 0
    for sig in sorted(set(a) | set(b)):
        name = re.sub(r"\(.*", "", sig).split(" ")[-1]
        if sig not in a and sig.startswith("private "):
            print("extra %s" % sig)
        elif sig not in a or sig not in b:
            print("FAIL  only in %s: %s" % ("ours" if sig in b else "stock", sig))
            bad += 1
        elif a[sig] == b[sig]:
            continue
        elif name in allowed:
            print("diff  %s (allowed)" % sig)
            for x in a[sig]:
                print("        stock  %-16s %s" % x)
            for x in b[sig]:
                print("        ours   %-16s %s" % x)
        else:
            print("FAIL  code differs: %s" % sig)
            n = max(len(a[sig]), len(b[sig]))
            for i in range(n):
                x = a[sig][i] if i < len(a[sig]) else ("", "")
                y = b[sig][i] if i < len(b[sig]) else ("", "")
                print("  %s %-60s | %s" % (" " if x == y else "*", "%s %s" % x, "%s %s" % y))
            bad += 1
    same = len([s for s in a if s in b and a[s] == b[s]])
    print("%d of %d stock methods have the same code" % (same, len(a)))
    print("BYTECODE_DIFF_OK" if bad == 0 else "BYTECODE_DIFF_FAILED (%d)" % bad)
    sys.exit(0 if bad == 0 else 1)


if __name__ == "__main__":
    main()
