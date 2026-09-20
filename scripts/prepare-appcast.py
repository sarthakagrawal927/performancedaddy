#!/usr/bin/env python3
"""Prepare a signed appcast from an already notarized DMG. Does not deploy."""
import argparse
from pathlib import Path
import hashlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import sparkle_support

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("release_directory", type=Path)
parser.add_argument("output", type=Path, help="New directory; must not already exist")
args = parser.parse_args()
sparkle_support.configuration()
sources = list(args.release_directory.glob("*.dmg"))
if len(sources) != 1:
    raise SystemExit("Expected exactly one release DMG")
source = sources[0]
match = re.fullmatch(r"PerformanceDaddy-(\d+(?:\.\d+)*)-(\d+)-universal\.dmg", source.name)
if not match:
    raise SystemExit(f"Unexpected release DMG name: {source.name}")
# Only signed, notarized and stapled releases can enter the appcast.
subprocess.run(["codesign", "--verify", "--verbose=2", str(source)], check=True)
subprocess.run(["xcrun", "stapler", "validate", str(source)], check=True)
sums = args.release_directory / "SHA256SUMS"
if sums.is_file() and hashlib.sha256(source.read_bytes()).hexdigest() not in sums.read_text():
    raise SystemExit("Release checksum mismatch")
args.output.mkdir(parents=True, exist_ok=False)
filename = f"performancedaddy-{match.group(1)}-build{match.group(2)}-universal.dmg"
shutil.copy2(source, args.output / filename)
tool = sparkle_support.ROOT / ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
subprocess.run([str(tool), "--account", "performancedaddy-updates", "--download-url-prefix",
                "https://performancedaddy.significanthobbies.com/updates/", str(args.output)], check=True)
feed = args.output / "appcast.xml"
root = ET.parse(feed).getroot()
enclosures = root.findall("./channel/item/enclosure")
if not enclosures:
    raise SystemExit("Empty update feed: do not publish")
for enclosure in enclosures:
    if not enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"):
        raise SystemExit("Unsigned enclosure: do not publish")
print(feed)
