#!/usr/bin/env python3
"""Propose a firmware profile for src/firmware_profiles.h from a unit's files.

    python3 tools/find_profile.py <gal> <libautoreceiver.so> [train-name]

The two files come from the green menu entry "Collect files for porting".
Needs the Python package `capstone` (pip install capstone).

What it derives, and how far to trust it:
  * the three fingerprint addresses      read from gal's symbol table: exact
  * the hidden constructor and its size  found by the shape of its one call
                                         site: a PROPOSAL, check the listing
  * the two controller offsets           read from that call site: a proposal
  * the handler table offsets            NOT derived; P4521's values are printed
                                         and must be checked by hand
  * the receiver library                 compared with the P4521 symbol layout

Nothing printed here is safe to ship until someone has read the disassembly it
points at and the result has run on a car with that firmware.
"""
import hashlib, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from armre import Elf  # noqa: E402

SYMS = (("controller_slot", "_ZN3gal14CGALController10s_instanceE"),
        ("impl_vtable", "_ZTVN3gal14CVideoSinkImplE"),
        ("cbhandler_vtable", "_ZTVN3gal25CVideoSinkCallbackHandlerE"))

# libautoreceiver.so symbols the hook interposes or calls, with their P4521 offsets.
RECEIVER = {
    "_ZN11GalReceiver15registerServiceEP20ProtocolEndpointBase": 0xe4928,
    "_ZN9VideoSink25addSupportedConfigurationEiiiiiii": 0xfafc4,
    "_ZN9VideoSink16addDiscoveryInfoEP24ServiceDiscoveryResponse": 0xfac34,
    "_ZN11InputSource16addDiscoveryInfoEP24ServiceDiscoveryResponse": 0xe6a84,
    "_ZN13MediaSinkBase10sendConfigEi": 0xec748,
    "_ZN13MediaSinkBase9ackFramesEij": 0xec294,
    "_ZN9VideoSink13setVideoFocusEib": 0xfa978,
    "_ZN9VideoSink11handleSetupEi": 0xfaa30,
    "_ZN9VideoSink19handleDataAvailableEyRK10shared_ptrI8IoBufferEj": 0xfa7f8,
    "_ZN9VideoSink17handleCodecConfigEPvj": 0xfa854,
    "_ZN9VideoSink13playbackStartEi": 0xfa8f4,
    "_ZN9VideoSink12playbackStopEi": 0xfa910,
    "_ZN9VideoSink24handleMediaConfigurationEi": 0xfa8d4,
    "_ZN9VideoSink23handleVideoFocusRequestERK29VideoFocusRequestNotification": 0xfa92c,
    "_ZN9VideoSink25getNumberOfConfigurationsEv": 0xfa95c,
    "_ZN13MessageRouter20handleChannelOpenReqEhRK18ChannelOpenRequest": 0xecc4c,
    "_ZN13MessageRouter12routeMessageEhRK10shared_ptrI8IoBufferE": 0xecf84,
    "_ZN13MessageRouter13queueOutgoingEhPvj": 0xecdac,
    "_ZN13MessageRouter24queueOutgoingUnencryptedEhPvj": 0xecef0,
    "_ZN13MessageRouter21sendUnexpectedMessageEh": 0xecf14,
    "_ZN10Controller18sendVersionRequestEv": 0xe2a30,
    "_ZTV9VideoSink": 0x103148,
    "_ZTV20ProtocolEndpointBase": 0x1030a8,
}
P4521_RECEIVER_SHA = "b04cb5cf3b8c9a003d2008844ff1434b6763a8e864b037251fafb65ce3a000c8"


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def imm(op):
    m = re.search(r"#(-?0x[0-9a-f]+|-?\d+)\s*$", op)
    return int(m.group(1), 0) if m else None


def find_ctor(g):
    """mov r0,#SIZE ; bl new ; add r1,rB,#A ; add r3,rB,#C ; bl CTOR  (any order of the adds)"""
    out = []
    for sec in g.secs:
        if not (sec[1] == 1 and sec[2] & 4 and sec[5] > 0x1000):
            continue
        ins = [l.split(None, 2) for l in g.dis(sec[3], sec[5])]
        ins = [(int(a[0].rstrip(":"), 16), a[1], a[2].split(";")[0].strip() if len(a) > 2 else "") for a in ins if len(a) >= 2]
        for i, (addr, mn, op) in enumerate(ins):
            if mn != "mov" or not op.startswith("r0, #"):
                continue
            size = imm(op)
            if size is None or not 0x60 <= size <= 0x400:
                continue
            j = next((k for k in range(i + 1, min(i + 4, len(ins))) if ins[k][1] == "bl"), None)
            if j is None:
                continue
            r1 = r3 = None
            for k in range(j + 1, min(j + 9, len(ins))):
                a, m, o = ins[k]
                mm = re.match(r"(r[13]), (r\d+|sb|sl|fp|ip), #", o) if m == "add" else None
                if mm:
                    if mm.group(1) == "r1": r1 = (mm.group(2), imm(o))
                    else: r3 = (mm.group(2), imm(o))
                if m == "bl":
                    if r1 and r3 and r1[0] == r3[0]:
                        out.append(dict(site=addr, size=size, new=imm(ins[j][2]), ctor=imm(o),
                                        cfg=r1[1], creator=r3[1], listing=ins[i:k + 1]))
                    break
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    gal_path, recv_path = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else "MHI2_xx_xxxxx_Pxxxx"
    g = Elf(gal_path)
    print(f"gal                {os.path.getsize(gal_path)} bytes  sha256 {sha(gal_path)}")
    print(f"libautoreceiver.so {os.path.getsize(recv_path)} bytes  sha256 {sha(recv_path)}\n")

    etype, = struct.unpack_from("<H", g.d, 0x10)
    if etype != 2:
        print("STOP: gal is not a fixed-address executable (ET_EXEC). The hook's absolute\n"
              "      addresses do not apply to this build at all.")
        return 1

    addr = {}
    by_name = {s[0]: s[1] for s in g.syms if s[4]}
    for field, sym in SYMS:
        addr[field] = by_name.get(sym)
        print(f"{field:17s} {('%#010x' % addr[field]) if addr[field] else 'MISSING'}  {sym}")
    if None in addr.values():
        print("\nSTOP: a fingerprint symbol is missing; this gal is a different design.")
        return 1

    cands = find_ctor(g)
    print(f"\nconstructor call-site candidates: {len(cands)}")
    for c in cands:
        first = g.u32(c["ctor"])
        c["first"] = first
        print(f"\n  site {c['site']:#x}: new({c['size']:#x}) then ctor {c['ctor']:#010x} "
              f"(first word {first:#010x}), r1 = controller+{c['cfg']:#x}, r3 = controller+{c['creator']:#x}")
        for a, m, o in c["listing"]:
            print(f"      {a:#x}: {m:6s} {o}")
    if len(cands) != 1:
        print("\nSTOP: expected exactly one candidate. Pick the right one by hand: the constructor\n"
              "      stores the CVideoSinkCallbackHandler vtable, and its site follows the VideoSink setup.")
        return 1
    c = cands[0]
    if c["first"] & 0xffff0000 != 0xe92d0000:
        print("\nWARNING: the constructor does not begin with a push instruction. Check it.")

    print("\n--- receiver library against the P4521 layout")
    r = Elf(recv_path)
    rn = {s[0]: s[1] for s in r.syms if s[4]}
    same = sha(recv_path) == P4521_RECEIVER_SHA
    if same:
        print("identical file to the P4521 receiver: every verified layout applies.")
    else:
        missing = [n for n in RECEIVER if n not in rn]
        moved = [(n, rn[n]) for n in RECEIVER if n in rn and rn[n] != RECEIVER[n]]
        print(f"different file. symbols missing: {len(missing)}, at a different offset: {len(moved)} of {len(RECEIVER)}")
        for n in missing: print(f"   MISSING {n}")
        for n, v in moved: print(f"   moved   {v:#x} (P4521 {RECEIVER[n]:#x})  {n}")
        print("The hook resolves these by name, so moved offsets are fine. What matters is that the\n"
              "object layouts in wiki/Receiver-Layout-Verification.md still hold: re-check each row.")
        if missing: print("STOP: a missing symbol means the hook cannot work with this receiver.")

    print("\n--- proposed entry for k_profiles[] in src/firmware_profiles.h  (car_tested = 0)")
    print(f"""    {{
        "{name}", 0,
        {addr['controller_slot']:#010x}u, {addr['impl_vtable']:#010x}u, {addr['cbhandler_vtable']:#010x}u,
        {c['ctor']:#010x}u, {c['first']:#010x}u, {c['size']:#x}u,
        {c['cfg']:#x}u, {c['creator']:#x}u,
        0x80u, 0x84u, 40u,          /* NOT derived: copied from P4521, verify */
        0x34u, 0x58u, 59u           /* NOT derived: copied from P4521, verify */
    }},""")
    print("\n--- or, to try it without rebuilding, one line in gal_dualscreen.conf")
    print(f"GAL_PROFILE_TRIAL={name}:{addr['controller_slot']:x}:{addr['impl_vtable']:x}:{addr['cbhandler_vtable']:x}:"
          f"{c['ctor']:x}:{c['first']:x}:{c['size']:x}:{c['cfg']:x}:{c['creator']:x}:80:84:28")
    print("\nNext: wiki/Porting-To-Another-Firmware.md, section 'Checking a proposed profile'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
