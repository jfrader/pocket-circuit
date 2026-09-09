#!/usr/bin/env python3
"""Install checksum-pinned official Godot build inputs without root or Docker."""

import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile


def install(destination: Path) -> dict[str, str]:
    manifest = json.loads(Path(__file__).with_name("godot_release.json").read_text())
    version = manifest["version"]
    base = f"https://github.com/godotengine/godot-builds/releases/download/{version}-stable/"
    destination.mkdir(parents=True, exist_ok=True)
    data_home = destination / "data"
    templates = data_home / "godot/export_templates" / f"{version}.stable"
    templates.mkdir(parents=True, exist_ok=True)
    editor_name = f"Godot_v{version}-stable_linux.x86_64"
    jobs = [
        (editor_name + ".zip", manifest["linux_editor_sha256"], {editor_name: destination / "godot"}),
        (f"Godot_v{version}-stable_export_templates.tpz", manifest["templates_sha256"], {
            "templates/linux_release.x86_64": templates / "linux_release.x86_64",
            "templates/windows_release_x86_64.exe": templates / "windows_release_x86_64.exe",
        }),
    ]
    for filename, expected, members in jobs:
        archive = destination / filename
        if not archive.exists():
            partial = archive.with_suffix(archive.suffix + ".partial")
            try:
                with urllib.request.urlopen(base + filename, timeout=90) as response, partial.open("wb") as output:
                    shutil.copyfileobj(response, output)
                partial.replace(archive)
            finally:
                partial.unlink(missing_ok=True)
        with archive.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected:
            archive.unlink()
            raise ValueError(f"Checksum mismatch for official asset {filename}")
        with zipfile.ZipFile(archive) as bundle:
            for member, output_path in members.items():
                with bundle.open(member) as source, output_path.open("wb") as output:
                    shutil.copyfileobj(source, output)
                output_path.chmod(0o755)
    return {"GODOT_BIN": str(destination / "godot"), "XDG_DATA_HOME": str(data_home)}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: install_ci_godot.py ABSOLUTE_INSTALL_DIRECTORY")
    root = Path(sys.argv[1])
    if not root.is_absolute():
        raise SystemExit("Install directory must be absolute")
    for key, value in install(root).items():
        print(f"{key}={value}")
