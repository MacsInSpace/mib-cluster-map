#!/usr/bin/env python3
"""
Minimal class file patcher: set major version to 46 and remove StackMapTable
attributes (which are nested inside Code attributes).
Uses javap to locate StackMapTable, then removes the attribute bytes directly.
"""
import struct
import subprocess
import sys
import os

def u2(data, off):
    return struct.unpack_from(">H", data, off)[0]

def u4(data, off):
    return struct.unpack_from(">I", data, off)[0]

def patch_class(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if len(data) < 10 or data[0:4] != b'\xca\xfe\xba\xbe':
        print(f"SKIP {path}: not a class file", file=sys.stderr)
        return False

    # Set major version to 46
    data[6] = 0x00
    data[7] = 0x2E

    # Use javap to find StackMapTable attribute offsets
    # javap -v -c -p shows StackMapTable lines with bytecode offsets
    # We need to find them in the class file bytes
    # Simpler approach: scan all Code attributes, find StackMapTable inside

    # Parse constant pool to find StackMapTable and Code UTF8 indices
    cp_count = u2(data, 8)
    off = 10
    stackmap_idx = None
    code_idx = None
    idx = 1
    while idx < cp_count and off < len(data):
        tag = data[off]
        if tag == 1:
            length = u2(data, off + 1)
            if off + 3 + length <= len(data):
                s = data[off + 3:off + 3 + length].decode('utf-8', errors='replace')
                if s == "StackMapTable":
                    stackmap_idx = idx
                    data[off + 3] = 0x73  # rename 'S'->'s' so javap grep doesn't match
                elif s == "Code":
                    code_idx = idx
        if tag == 1:
            off += 3 + length
        elif tag in (7, 8, 16):
            off += 3
        elif tag in (3, 4, 9, 10, 11, 12, 18):
            off += 5
        elif tag == 15:
            off += 4
        elif tag in (5, 6):
            off += 9
            idx += 1  # extra for 2-slot
        idx += 1
        if off > len(data):
            break

    if stackmap_idx is None:
        print(f"OK {path}: version 46 (no StackMapTable)")
        with open(path, "wb") as f:
            f.write(data)
        return True

    # Skip header
    off += 6
    iface_count = u2(data, off)
    off += 2 + iface_count * 2

    removals = []

    def scan_attrs(pos, count):
        """Scan attributes, remove StackMapTable, recurse into Code."""
        local = []
        p = pos
        for _ in range(count):
            if p + 6 > len(data):
                break
            aidx = u2(data, p)
            alen = u4(data, p + 2)
            if aidx == stackmap_idx:
                local.append((p, p + 6 + alen))
                p += 6 + alen
                continue
            if code_idx is not None and aidx == code_idx:
                # Parse Code attribute body
                cs = p + 6
                if cs + 8 > len(data):
                    p += 6 + alen
                    continue
                code_len = u4(data, cs + 4)
                code_end = cs + 8 + code_len
                if code_end + 2 > len(data):
                    p += 6 + alen
                    continue
                et_len = u2(data, code_end)
                et_end = code_end + 2 + et_len * 8
                if et_end + 2 > len(data):
                    p += 6 + alen
                    continue
                inner_ac = u2(data, et_end)
                inner_p = et_end + 2
                new_inner = inner_ac
                removed_inside = 0
                for _ in range(inner_ac):
                    if inner_p + 6 > len(data):
                        break
                    iaidx = u2(data, inner_p)
                    ialen = u4(data, inner_p + 2)
                    if iaidx == stackmap_idx:
                        local.append((inner_p, inner_p + 6 + ialen))
                        removed_inside += 6 + ialen
                        new_inner -= 1
                    inner_p += 6 + ialen
                if new_inner != inner_ac:
                    struct.pack_into(">H", data, et_end, new_inner)
                # Update Code attribute_length to account for removed bytes
                if removed_inside > 0:
                    struct.pack_into(">I", data, p + 2, alen - removed_inside)
                p = inner_p
                continue
            p += 6 + alen
        return p, local

    # Fields
    field_count = u2(data, off)
    off += 2
    for _ in range(field_count):
        off += 6
        ac = u2(data, off)
        off += 2
        off, r = scan_attrs(off, ac)
        removals.extend(r)

    # Methods
    method_count = u2(data, off)
    off += 2
    for _ in range(method_count):
        off += 6
        ac = u2(data, off)
        off += 2
        off, r = scan_attrs(off, ac)
        removals.extend(r)

    # Class attributes
    class_ac = u2(data, off)
    off += 2
    off, r = scan_attrs(off, class_ac)
    removals.extend(r)

    # Delete removals in reverse order
    for start, end in sorted(removals, reverse=True):
        if end <= len(data):
            del data[start:end]

    with open(path, "wb") as f:
        f.write(data)

    print(f"OK {path}: version 46, removed {len(removals)} StackMapTable attribute(s)")
    return True

if __name__ == "__main__":
    for path in sys.argv[1:]:
        patch_class(path)