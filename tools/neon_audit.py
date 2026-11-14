#!/usr/bin/env python3
"""List the NEON loads and stores in a disassembly that QNX may stop.

    python3 tools/neon_audit.py build/stream-player.dis [allowlist]

The QNX kernel of the MHI2 units runs with strict alignment: a NEON vld/vst
of 16, 32 or 64-bit elements faults (SIGBUS) unless the address is a multiple
of the element size. Byte-sized (.8) accesses never fault, and an access with
an alignment qualifier (":64" and so on) faults on Linux as well, so FFmpeg
already guarantees those.

That leaves vld/vst of 16/32/64-bit elements WITHOUT a qualifier. Each one is
printed with its function. The allowlist (tools/neon_audit.allow) names the
functions whose pointers were checked by hand to be aligned, with the reason.
Any other function with such an access fails the build.

The disassembly is "objdump -d" of the unstripped player (build_local.sh).
"""
import re, sys

def main():
    dis = sys.argv[1]
    allow = {}
    if len(sys.argv) > 2:
        for line in open(sys.argv[2]):
            line = line.split('#')[0].strip()
            if line:
                allow[line.split()[0]] = 1
    sym = None
    risky = {}       # function -> list of instructions
    total = neon_total = 0
    sym_re = re.compile(r'^[0-9a-f]+ <([^>]+)>:')
    ins_re = re.compile(r'^\s*[0-9a-f]+:\s+[0-9a-f]+\s+(v(?:ld|st)[1-4])\.(8|16|32|64)\s+(.*)$')
    for line in open(dis, errors='replace'):
        m = sym_re.match(line)
        if m:
            sym = m.group(1)
            continue
        m = ins_re.match(line)
        if not m:
            continue
        neon_total += 1
        op, size, rest = m.group(1), int(m.group(2)), m.group(3)
        rest = rest.split(';')[0].strip()
        if size == 8:
            continue
        if re.search(r':\s*\d+', rest.split('[')[-1]):
            continue        # alignment qualifier present
        total += 1
        risky.setdefault(sym, []).append('%s.%d %s' % (op, size, rest))
    bad = 0
    for f in sorted(risky):
        tag = 'checked' if f in allow else 'NOT CHECKED'
        if f not in allow:
            bad += 1
        print('%-11s %s (%d)' % (tag, f, len(risky[f])))
        for i in sorted(set(risky[f])):
            print('              %s' % i)
    print('neon_audit: %d NEON loads/stores, %d of 16/32/64 bits without an alignment qualifier, in %d functions, %d not checked'
          % (neon_total, total, len(risky), bad))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
