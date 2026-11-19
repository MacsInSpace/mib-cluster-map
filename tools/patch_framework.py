#!/usr/bin/env python3
"""
Patch de.audi.atip.base.FrameworkAccess.class to load our AA provider.

Patches the FrameworkAccess(BundleContext) constructor to, right after storing
the BundleContext into the `context` field, call:

    AAJavaBridge.setBundleContext(this.context);
    AAJavaBridge.init();

This forces J9 to load AAJavaBridge when FrameworkAccess is constructed during
Audi framework startup. AAJavaBridge's static initializer creates AATrackProvider
and AAManeuverProvider, which use AAJavaBridge.getBundleContext() to obtain the
real BundleContext, look up the DSIAndroidAuto2 OSGi service, call
setNotification(this) and startService(ServiceConfiguration).

Constant pool entries added:
  CONSTANT_Utf8: "com/mhi2/androidadio/AAJavaBridge"
  CONSTANT_Class: com/mhi2/androidadio/AAJavaBridge
  CONSTANT_Utf8: "setBundleContext"
  CONSTANT_Utf8: "(Lorg/osgi/framework/BundleContext;)V"
  CONSTANT_NameAndType: setBundleContext:(Lorg/osgi/framework/BundleContext;)V
  CONSTANT_Methodref: AAJavaBridge.setBundleContext
  CONSTANT_Utf8: "init"
  CONSTANT_Utf8: "()V"
  CONSTANT_NameAndType: init:()V
  CONSTANT_Methodref: AAJavaBridge.init

Bytecode inserted in FrameworkAccess(BundleContext) constructor after
`putfield context` (offset 11):

    aload_0                      // load this
    getfield #80                 // get context field
    invokestatic AAJavaBridge.setBundleContext:(Lorg/osgi/framework/BundleContext;)V
    invokestatic AAJavaBridge.init:()V

Also sets major version to 46 (already 46 in the stock file).
"""
import struct
import sys
import os


def u2(data, off):
    return struct.unpack_from(">H", data, off)[0]


def u4(data, off):
    return struct.unpack_from(">I", data, off)[0]


def skip_cp_entry(data, off):
    """Return offset just past the CP entry starting at off (tag byte included)."""
    tag = data[off]
    off += 1
    if tag == 1:  # Utf8
        length = u2(data, off)
        off += 2 + length
    elif tag in (7, 8, 16):  # Class, String, MethodType
        off += 2
    elif tag in (3, 4, 9, 10, 11, 12, 18):  # 4-byte types
        off += 4
    elif tag == 15:  # MethodHandle
        off += 3
    elif tag in (5, 6):  # Long, Double (wide, 2 CP slots)
        off += 8
    return off


def parse_cp(data):
    """Parse constant pool, return (cp_count, cp_end_offset, entries list)."""
    cp_count = u2(data, 8)
    entries = []
    off = 10
    idx = 1
    while idx < cp_count:
        start = off
        tag = data[off]
        off = skip_cp_entry(data, off)
        entries.append((idx, tag, data[start:off], start))
        if tag in (5, 6):
            idx += 2  # wide item takes 2 CP slots
        else:
            idx += 1
    return cp_count, off, entries


def find_utf8(data, entries, s):
    """Find CP index of Utf8 entry with string value s."""
    for idx, tag, val, start in entries:
        if tag == 1:
            str_start = start + 1
            length = u2(data, str_start)
            try:
                str_bytes = data[str_start + 2:str_start + 2 + length]
                if str_bytes.decode('utf-8') == s:
                    return idx
            except Exception:
                pass
    return None


def find_class(data, entries, class_name_utf8_idx):
    """Find CONSTANT_Class index whose name points to given Utf8 index."""
    for idx, tag, val, start in entries:
        if tag == 7:
            name_idx = u2(val, 1)
            if name_idx == class_name_utf8_idx:
                return idx
    return None


def find_methodref(data, entries, class_idx, nt_idx):
    """Find CONSTANT_Methodref index matching class and name_and_type."""
    for idx, tag, val, start in entries:
        if tag == 10:
            c_idx = u2(val, 1)
            n_idx = u2(val, 3)
            if c_idx == class_idx and n_idx == nt_idx:
                return idx
    return None


def find_name_and_type(data, entries, name_idx, desc_idx):
    """Find CONSTANT_NameAndType index matching name and descriptor."""
    for idx, tag, val, start in entries:
        if tag == 12:
            n_idx = u2(val, 1)
            d_idx = u2(val, 3)
            if n_idx == name_idx and d_idx == desc_idx:
                return idx
    return None


def find_string(data, entries, utf8_idx):
    """Find CONSTANT_String index pointing to given Utf8 index."""
    for idx, tag, val, start in entries:
        if tag == 8:
            string_idx = u2(val, 1)
            if string_idx == utf8_idx:
                return idx
    return None


def skip_attribute(data, off):
    """Skip one attribute, return offset past it."""
    aidx = u2(data, off)
    alen = u4(data, off + 2)
    return off + 6 + alen


def skip_attributes(data, off, count):
    """Skip count attributes, return offset past them."""
    for _ in range(count):
        off = skip_attribute(data, off)
    return off


def patch_framework_access(path, out_path=None):
    if out_path is None:
        out_path = path

    with open(path, "rb") as f:
        data = bytearray(f.read())

    if len(data) < 10 or data[0:4] != b'\xca\xfe\xba\xbe':
        print(f"SKIP {path}: not a class file", file=sys.stderr)
        return False

    minor = u2(data, 4)
    major = u2(data, 6)
    print(f"  version: {major}.{minor}")

    # Set major version to 46 (already 46, but ensure it)
    data[6] = 0x00
    data[7] = 0x2E

    # Parse constant pool
    cp_count, cp_end, entries = parse_cp(data)

    # Helper lookups using existing CP
    bundlecontext_utf8 = find_utf8(data, entries, "org/osgi/framework/BundleContext")
    bundlecontext_class = find_class(data, entries, bundlecontext_utf8)
    print(f"  BundleContext Utf8=#{bundlecontext_utf8}, Class=#{bundlecontext_class}")

    # ForName methodref already exists (#2), java/lang/Class (#62)
    class_class = find_class(data, entries, find_utf8(data, entries, "java/lang/Class"))
    forname_nt = find_name_and_type(
        data, entries,
        find_utf8(data, entries, "forName"),
        find_utf8(data, entries, "(Ljava/lang/String;)Ljava/lang/Class;")
    )
    forname_mref = find_methodref(data, entries, class_class, forname_nt)
    print(f"  Class.forName methodref=#{forname_mref}")

    # Build new constant pool entries
    # We need:
    # 1. Utf8 "com/mhi2/androidadio/AAJavaBridge"
    # 2. Class AAJavaBridge (ref to #1)
    # 3. Utf8 "setBundleContext"
    # 4. Utf8 "(Lorg/osgi/framework/BundleContext;)V"
    # 5. NameAndType #3:#4
    # 6. Methodref #2:#5 (AAJavaBridge.setBundleContext)
    # 7. Utf8 "init"
    # 8. Utf8 "()V"
    # 9. NameAndType #7:#8
    # 10. Methodref #2:#9 (AAJavaBridge.init)

    new_cp_entries = bytearray()

    def append_utf8(s):
        b = s.encode('utf-8')
        new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)
        return len(new_cp_entries)  # placeholder, will track indices separately

    # Track new entry indices (starting from cp_count)
    new_idx = cp_count

    # 1. Utf8 "com/mhi2/androidadio/AAJavaBridge"
    aa_cls_utf8_idx = new_idx
    new_idx += 1
    b = b"com/mhi2/androidadio/AAJavaBridge"
    new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)

    # 2. Class AAJavaBridge
    aa_cls_idx = new_idx
    new_idx += 1
    new_cp_entries.extend(bytes([7]) + struct.pack(">H", aa_cls_utf8_idx))

    # 3. Utf8 "setBundleContext"
    sb_name_utf8_idx = new_idx
    new_idx += 1
    b = b"setBundleContext"
    new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)

    # 4. Utf8 "(Lorg/osgi/framework/BundleContext;)V"
    sb_desc_utf8_idx = new_idx
    new_idx += 1
    b = b"(Lorg/osgi/framework/BundleContext;)V"
    new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)

    # 5. NameAndType setBundleContext:(Lorg/osgi/framework/BundleContext;)V
    sb_nt_idx = new_idx
    new_idx += 1
    new_cp_entries.extend(bytes([12]) + struct.pack(">HH", sb_name_utf8_idx, sb_desc_utf8_idx))

    # 6. Methodref AAJavaBridge.setBundleContext
    sb_mref_idx = new_idx
    new_idx += 1
    new_cp_entries.extend(bytes([10]) + struct.pack(">HH", aa_cls_idx, sb_nt_idx))

    # 7. Utf8 "init"
    init_name_utf8_idx = new_idx
    new_idx += 1
    b = b"init"
    new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)

    # 8. Utf8 "()V"
    init_desc_utf8_idx = new_idx
    new_idx += 1
    b = b"()V"
    new_cp_entries.extend(bytes([1]) + struct.pack(">H", len(b)) + b)

    # 9. NameAndType init:()V
    init_nt_idx = new_idx
    new_idx += 1
    new_cp_entries.extend(bytes([12]) + struct.pack(">HH", init_name_utf8_idx, init_desc_utf8_idx))

    # 10. Methodref AAJavaBridge.init
    init_mref_idx = new_idx
    new_idx += 1
    new_cp_entries.extend(bytes([10]) + struct.pack(">HH", aa_cls_idx, init_nt_idx))

    # Update cp_count
    new_cp_count = new_idx
    struct.pack_into(">H", data, 8, new_cp_count)

    # Insert new CP entries at cp_end position
    data[cp_end:cp_end] = new_cp_entries
    cp_entries_size = len(new_cp_entries)
    print(f"  Added {new_cp_count - cp_count} CP entries, {cp_entries_size} bytes")

    # Now everything after cp_end is shifted by cp_entries_size.
    # Find the constructor method and its Code attribute.
    # Structure after CP:
    #   access_flags(2) this_class(2) super_class(2) interfaces(2+n*2)
    #   fields_count(2) fields...
    #   methods_count(2) methods...
    #   attributes_count(2) attributes...

    p = cp_end + cp_entries_size  # adjusted for inserted CP

    # access_flags, this_class, super_class
    p += 6
    iface_count = u2(data, p)
    p += 2 + iface_count * 2

    # Fields
    field_count = u2(data, p)
    p += 2
    for _ in range(field_count):
        p += 6  # access_flags, name_index, descriptor_index
        ac = u2(data, p)
        p += 2
        p = skip_attributes(data, p, ac)

    # Methods
    method_count = u2(data, p)
    p += 2

    constructor_code_start = None
    constructor_code_length_off = None
    constructor_attr_length_off = None

    for m_idx in range(method_count):
        m_start = p
        m_acc_flags = u2(data, p); p += 2
        m_name_idx = u2(data, p); p += 2
        m_desc_idx = u2(data, p); p += 2
        m_attr_count = u2(data, p); p += 2

        # Check if this is the constructor FrameworkAccess(BundleContext)
        name_str = None
        desc_str = None
        for idx, tag, val, start in entries:
            if idx == m_name_idx and tag == 1:
                str_start = start + 1
                length = u2(data, str_start)
                name_str = data[str_start + 2:str_start + 2 + length].decode('utf-8', errors='replace')
            if idx == m_desc_idx and tag == 1:
                str_start = start + 1
                length = u2(data, str_start)
                desc_str = data[str_start + 2:str_start + 2 + length].decode('utf-8', errors='replace')

        is_init = (name_str == "<init>")
        is_bundle_ctx_ctor = (desc_str == "(Lorg/osgi/framework/BundleContext;)V")

        for _ in range(m_attr_count):
            aidx = u2(data, p); p += 2
            alen = u4(data, p); p += 4
            # Check if this is the Code attribute
            attr_name_str = None
            for idx, tag, val, start in entries:
                if idx == aidx and tag == 1:
                    str_start = start + 1
                    length = u2(data, str_start)
                    attr_name_str = data[str_start + 2:str_start + 2 + length].decode('utf-8', errors='replace')
                    break

            if attr_name_str == "Code" and is_init and is_bundle_ctx_ctor:
                # Found the constructor's Code attribute
                # Code structure:
                #   attribute_name_index(2) attribute_length(4)
                #   max_stack(2) max_locals(2) code_length(4)
                #   code(code_length bytes)
                #   exception_table_length(2) exception_table(...)
                #   attributes_count(2) attributes(...)
                # p currently points after attribute_length (at max_stack)
                code_start = p + 2 + 2 + 4  # skip max_stack, max_locals, code_length field position
                code_length_off = p + 2 + 2  # offset of code_length field
                # attribute_length_off is 4 bytes before max_stack
                constructor_attr_length_off = p - 6  # attribute_name_index(2) + attribute_length(4)
                constructor_code_start = code_start
                constructor_code_length_off = code_length_off
                print(f"  Found constructor Code attr at code offset {code_start}, code_length field at {code_length_off}")

            p += alen  # skip attribute data

        # Continue to next method (p already points past attributes)

    if constructor_code_start is None:
        print("  ERROR: Could not find FrameworkAccess(BundleContext) constructor Code attribute", file=sys.stderr)
        return False

    # Read current code_length
    code_length = u4(data, constructor_code_length_off)
    print(f"  Constructor code_length: {code_length}")

    # We need to insert bytecode after `putfield context` at offset 11 within the code.
    # putfield is at offset 11, 3 bytes (opcode + 2 index bytes). Next instruction at offset 14.
    # Insertion point = constructor_code_start + 14
    insert_point = constructor_code_start + 14

    # Verify: at offset 11 within code, we should see putfield opcode (0xb3)
    code_offset_11 = constructor_code_start + 11
    if data[code_offset_11] != 0xb3:
        print(f"  WARNING: Expected putfield (0xb3) at code offset 11, found 0x{data[code_offset_11]:02x}", file=sys.stderr)

    # New bytecode to insert:
    #   aload_0        = 0x2a (1 byte)
    #   getfield #80   = 0xb4 + 2-byte index (3 bytes)
    #   invokestatic sb_mref_idx = 0xb8 + 2-byte index (3 bytes)
    #   invokestatic init_mref_idx = 0xb8 + 2-byte index (3 bytes)
    # Total: 10 bytes
    new_code = bytearray()
    new_code.append(0x2a)  # aload_0
    new_code.append(0xb4)  # getfield
    new_code.extend(struct.pack(">H", 80))  # fieldref #80 = context field
    new_code.append(0xb8)  # invokestatic
    new_code.extend(struct.pack(">H", sb_mref_idx))
    new_code.append(0xb8)  # invokestatic
    new_code.extend(struct.pack(">H", init_mref_idx))

    print(f"  Inserting {len(new_code)} bytes at code offset 14")

    # Insert the new code bytes
    data[insert_point:insert_point] = new_code

    # Update code_length (+10 bytes)
    new_code_length = code_length + len(new_code)
    struct.pack_into(">I", data, constructor_code_length_off, new_code_length)

    # Update Code attribute_length (+10 bytes)
    attr_length_off = constructor_attr_length_off + 2  # attribute_length is 4 bytes after attribute_name_index
    current_attr_len = u4(data, attr_length_off)
    struct.pack_into(">I", data, attr_length_off, current_attr_len + len(new_code))
    print(f"  Code attribute_length: {current_attr_len} -> {current_attr_len + len(new_code)}")

    # Write patched file
    with open(out_path, "wb") as f:
        f.write(data)

    print(f"  OK: Patched {path} -> {out_path}")
    print(f"    - Added {new_cp_count - cp_count} CP entries")
    print(f"    - Inserted {len(new_code)} bytes in constructor")
    print(f"    - New code_length: {new_code_length}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch_framework.py <FrameworkAccess.class> [output.class]", file=sys.stderr)
        sys.exit(1)
    out = sys.argv[2] if len(sys.argv) > 2 else None
    patch_framework_access(sys.argv[1], out)