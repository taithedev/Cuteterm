"""Create reproducible-ish Windows release assets from the compiled Rust binaries.

No runtime Python or PowerShell dependency. Used only in GitHub Actions.
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOML = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
MATCH = re.search(r'(?m)^version = "(\d+\.\d+\.\d+)"$', TOML)
if not MATCH:
    sys.exit("Cannot determine Rust package version")
VERSION = MATCH.group(1)
ISS = (ROOT / "installer" / "CuteTerm.iss").read_text(encoding="utf-8")
if f'#define MyAppVersion "{VERSION}"' not in ISS:
    sys.exit("Rust package version and Inno Setup version differ")

BUILD = ROOT / "target" / "release"
DIST = ROOT / "dist"
DIST.mkdir(exist_ok=True)
MAIN = BUILD / "cuteterm.exe"
UPDATER = BUILD / "cuteterm-updater.exe"
INSTALLER = ROOT / "installer" / "Output" / f"CuteTerm-Windows-Setup-{VERSION}.exe"
for item in (MAIN, UPDATER, INSTALLER):
    if not item.is_file() or item.stat().st_size == 0:
        sys.exit(f"Required compiled Windows binary was not found: {item}")

def checksum(path: pathlib.Path) -> None:
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_name(path.name + ".sha256").write_text(
        f"{sha} *{path.name}\n", encoding="ascii", newline="\n"
    )
    print(f"{path.name}: {path.stat().st_size:,} bytes; sha256 {sha}")

# In-app auto updater replaces only the Rust application binary. It never runs
# arbitrary scripts from downloaded ZIPs, nor extracts untrusted archive paths.
zip_path = DIST / "CuteTerm-Windows-x64.zip"
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    archive.write(MAIN, arcname="cuteterm.exe")
checksum(zip_path)

setup_path = DIST / INSTALLER.name
shutil.copy2(INSTALLER, setup_path)
checksum(setup_path)
print(f"CuteTerm v{VERSION} Windows x64 release assets ready.")
