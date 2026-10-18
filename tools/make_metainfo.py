#!/usr/bin/env python3
"""Write the software-update metadata for the SD card package.

    python3 tools/make_metainfo.py <sdcard dir> <version label>

Produces <sdcard>/metainfo2.txt and <sdcard>/ClusterMap/final/hashes.txt.

The format follows the MQB Coding MIB2 Toolbox, which installs itself on a
stock unit the same way: a signed header taken unchanged from the toolbox
(thirdparty/mib2-toolbox/metainfo2_signed_header.bin), followed by a second
[common] section that names a final script. Checksums are SHA-1, as the
toolbox's own values confirm for its final script and its menu file.
"""
import hashlib, os, sys

def sha1(path):
    return hashlib.sha1(open(path, "rb").read()).hexdigest()

def main():
    card, version = sys.argv[1], sys.argv[2]
    here = os.path.dirname(os.path.abspath(__file__))
    header = open(os.path.join(here, "..", "thirdparty", "mib2-toolbox", "metainfo2_signed_header.bin"), "rb").read()
    final_dir = os.path.join(card, "ClusterMap", "final")
    script = os.path.join(final_dir, "finalScript.sh")
    esd = os.path.join(card, "ClusterMap", "GEM", "cluster-map.esd")
    for p in (script, esd):
        data = open(p, "rb").read()
        if b"\r" in data or any(c > 127 for c in data):
            sys.exit(f"{p}: must be LF and ASCII")

    # Every file in final/, as the toolbox lists its final script and the
    # script that script runs.
    names = sorted(n for n in os.listdir(final_dir) if n.endswith(".sh"))
    hashes = "".join(
        f'FileName = "{n}"\nFileSize = "{os.path.getsize(os.path.join(final_dir, n))}"\n'
        f'CheckSum = "{sha1(os.path.join(final_dir, n))}"\n\n' for n in names)
    hpath = os.path.join(final_dir, "hashes.txt")
    open(hpath, "w", newline="\n").write(hashes)
    dir_size = sum(os.path.getsize(os.path.join(final_dir, n)) for n in names) + os.path.getsize(hpath)

    numeric = "".join(c for c in version if c.isdigit()) or "1"
    body = f'''[common]
skipSaveTrainName = "true"
vendor = "MQB.Coding"
skipCheckSignatureAndVariant = "true"
region = "Europe"
region2 = "RoW"
region3 = "USA"
region4 = "Japan"
region5 = "China"
region6 = "Taiwan"
variant = "FM?-*-*-*-*"
release = "MIB Cluster Map {version}"
skipMetaCRC = "true"
skipFileCopyCrc = "true"
skipCheckVariant = "true"
skipCheckRegion = "true"
FinalScript = "./ClusterMap/final/finalScript.sh"
FinalScriptChecksum = "{sha1(script)}"
FinalScriptMaxTime = "30"
FinalScriptName = "Final Script"

[ClusterMap\\final\\Dir]
FileSize = "{dir_size}"
CheckSum = "{sha1(hpath).upper()}"

[ClusterMap]
VendorInfo = "MQB.Coding"
DeviceDescription = "MIB Cluster Map"
DownloadGroup = "ClusterMap"

[ClusterMap\\GEM\\0\\default\\File]
checkUpdate = "true"
CheckSumSize = "524288"
CheckSum = "{sha1(esd)}"
FileSize = "{os.path.getsize(esd)}"
Version = "{numeric}"
Source = "../../cluster-map.esd"
Destination = "/net/mmx/mnt/app/eso/hmi/engdefs/cluster-map.esd"
DisplayName = "MIB Cluster Map"
DeleteDestinationDirBeforeCopy = "false"
UpdateOnlyExisting = "false"
'''
    out = header + body.replace("\n", "\r\n").encode("ascii")
    open(os.path.join(card, "metainfo2.txt"), "wb").write(out)
    print(f"metainfo2.txt: {len(out)} bytes, final script sha1 {sha1(script)}")

if __name__ == "__main__":
    main()
