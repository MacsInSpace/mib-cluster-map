#!/usr/bin/env python3
"""ARM ELF helper (capstone). armre.py <elf> list [substr] | dis <sym-substr|0xaddr> [len] | words <0xaddr> <n>"""
import struct, sys
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB
class Elf:
    def __init__(s, path):
        d = s.d = open(path, 'rb').read()
        shoff, = struct.unpack_from('<I', d, 0x20); es, n, _ = struct.unpack_from('<HHH', d, 0x2e)
        s.secs = [struct.unpack_from('<IIIIIIIIII', d, shoff + i*es) for i in range(n)]
        s.syms = []; s.symtab = []
        for sec in s.secs:
            if sec[1] == 11:
                st = s.secs[sec[6]]
                for i in range(sec[5] // 16):
                    nm, v, sz, info, oth, shndx = struct.unpack_from('<IIIBBH', d, sec[4] + i*16)
                    e = d.index(b'\0', st[4] + nm); name = d[st[4]+nm:e].decode()
                    s.symtab.append(name); s.syms.append((name, v, sz, info & 15, shndx))
        s.byaddr = {}
        for nm, v, sz, t, sh in s.syms:
            if sh and v: s.byaddr.setdefault(v & ~1, nm)
        s.rel = {}   # addr -> description
        for sec in s.secs:
            if sec[1] == 9:
                for i in range(sec[5] // 8):
                    off, info = struct.unpack_from('<II', d, sec[4] + i*8)
                    t, si = info & 0xff, info >> 8
                    if t == 23:
                        o = s.off(off); a = struct.unpack_from('<I', d, o)[0] if o is not None else 0
                        s.rel[off] = ('rel', a, s.byaddr.get(a & ~1, ''))
                    else:
                        nm, v = s.symtab[si], s.syms[si][1]
                        s.rel[off] = ('sym', v, nm)
        s.plt = {}
    def off(s, va):
        for sec in s.secs:
            if sec[3] and sec[1] != 8 and sec[3] <= va < sec[3] + sec[5]: return sec[4] + va - sec[3]
    def u32(s, va):
        o = s.off(va); return struct.unpack_from('<I', s.d, o)[0] if o is not None else None
    def name(s, va):
        va &= ~1
        if va in s.byaddr: return s.byaddr[va]
        # PLT stub: add ip,pc,#a ; add ip,ip,#b ; ldr pc,[ip,#c]!
        o = s.off(va)
        if o is None: return ''
        try:
            md = Cs(CS_ARCH_ARM, CS_MODE_ARM); ins = list(md.disasm(s.d[o:o+12], va))
            if len(ins) == 3 and ins[0].mnemonic == 'add' and ins[2].mnemonic == 'ldr' and 'pc' in ins[2].op_str:
                a = int(ins[0].op_str.split('#')[1], 0); b = int(ins[1].op_str.split('#')[1], 0)
                c = int(ins[2].op_str.split('#')[1].rstrip(']!'), 0)
                got = va + 8 + a + b + c
                r = s.rel.get(got)
                if r: return 'plt:' + r[2]
        except Exception: pass
        return ''
    def dis(s, v, sz, thumb=False):
        md = Cs(CS_ARCH_ARM, CS_MODE_THUMB if thumb else CS_MODE_ARM)
        md.skipdata = True; o = s.off(v); out = []
        for i in md.disasm(s.d[o:o+sz], v):
            c = ''
            if i.mnemonic.startswith('b') and '#0x' in i.op_str and i.mnemonic not in ('bic', 'bics'):
                t = int(i.op_str.split('#')[-1], 0); c = s.name(t)
                if not (v <= t < v + sz) or c: c = '; ' + (c or '')
            elif 'pc' in i.op_str and i.mnemonic == 'ldr' and '#' in i.op_str:
                try:
                    k = int(i.op_str.split('#')[-1].rstrip(']'), 0); a = (i.address + 8 + k)
                    w = s.u32(a); c = f'; ={w:#x} {s.byaddr.get(w & ~1, "")}'
                except Exception: pass
            out.append(f'{i.address:#08x}: {i.mnemonic:7s} {i.op_str} {c}')
        return out
def find(e, a):
    m = [x for x in e.syms if a in x[0] and x[4]]; m.sort(key=lambda x: len(x[0])); return m[0]
if __name__ == '__main__':
    e = Elf(sys.argv[1]); cmd = sys.argv[2]
    if cmd == 'list':
        pat = sys.argv[3] if len(sys.argv) > 3 else ''
        for n, v, sz, t, sh in sorted(e.syms, key=lambda x: x[1]):
            if pat in n and sh: print(f'{v:#08x} {sz:6d} {t} {n}')
    elif cmd == 'dis':
        for a in sys.argv[3:]:
            if a.startswith('0x'):
                v, sz = (int(x, 16) for x in (a.split(':') + ['0x80'])[:2]); nm = a
            else: nm, v, sz, _, _ = find(e, a)
            print(f';;; {nm} @ {v:#x} size {sz}'); print('\n'.join(e.dis(v & ~1, sz, v & 1))); print()
    elif cmd == 'words':
        v, n = int(sys.argv[3], 16), int(sys.argv[4], 0)
        for i in range(n):
            a = v + 4*i; r = e.rel.get(a)
            print(f'{a:#08x}: {e.u32(a):#010x} {("-> %#x %s" % (r[1], r[2])) if r else ""}')
