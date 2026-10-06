#!/usr/bin/env python3
"""Install checksum-pinned official Godot build inputs without root or Docker."""

import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.error
import urllib.request
import zipfile


def _fetch(url: str, dest: Path) -> tuple[int, int | None]:
    """Download body from url into dest (binary write). Return (http_status, content_length or None).

    Raises on failure to connect or read.
    """
    with urllib.request.urlopen(url, timeout=90) as response:
        cl_header = response.getheader("Content-Length")
        content_length = int(cl_header) if cl_header else None
        with dest.open("wb") as output:
            shutil.copyfileobj(response, output)
        return response.status, content_length


def _ensure_archive(
    archive: Path,
    url: str,
    expected_sha: str,
    filename: str,
    fetch: callable,
) -> None:
    """Ensure the archive file exists at `archive` with matching sha256.

    Uses bounded retry+backoff for transient failures (network, short reads, corrupt bodies).
    Each attempt writes to a sibling .partN temp, verifies size (if known) + sha before atomic replace.
    On mismatch or error, temp is removed; no partials left on return or exception.
    If a verified archive already exists, the fetch is skipped (cache friendly).
    On permanent failure raises ValueError with HTTP status, bytes vs expected, sha details.
    """
    if archive.exists():
        with archive.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual == expected_sha:
            return
        archive.unlink(missing_ok=True)

    attempts = 3
    backoff = 1
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        temp = archive.with_name(f"{archive.name}.part{attempt}")
        temp.unlink(missing_ok=True)
        try:
            try:
                status, expected_size = fetch(url, temp)
            except urllib.error.HTTPError as http_err:
                status = http_err.code
                expected_size = None
                if temp.exists():
                    temp.unlink(missing_ok=True)
                raise ValueError(
                    f"HTTP {status} error for official asset {filename} "
                    f"(attempt {attempt}/{attempts}): {http_err.reason}"
                ) from http_err
            except Exception as net_err:
                if temp.exists():
                    temp.unlink(missing_ok=True)
                raise ValueError(
                    f"Transient download error for official asset {filename} "
                    f"(attempt {attempt}/{attempts}): {type(net_err).__name__}: {net_err}"
                ) from net_err

            received = temp.stat().st_size if temp.exists() else 0
            if expected_size is not None and received != expected_size:
                temp.unlink(missing_ok=True)
                raise ValueError(
                    f"Size mismatch for official asset {filename}: "
                    f"HTTP {status}, received {received} bytes vs expected {expected_size} "
                    f"(attempt {attempt})"
                )

            with temp.open("rb") as stream:
                actual = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual != expected_sha:
                temp.unlink(missing_ok=True)
                raise ValueError(
                    f"Checksum mismatch for official asset {filename}: "
                    f"HTTP {status}, bytes received {received} vs expected {expected_size or 'unknown'}, "
                    f"computed {actual} != {expected_sha} "
                    f"(attempt {attempt})"
                )

            # verified good, commit atomically
            temp.replace(archive)
            return
        except Exception as exc:
            last_exc = exc
            if temp.exists():
                temp.unlink(missing_ok=True)
            if attempt < attempts:
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)
            # continue to retry
    assert last_exc is not None
    raise last_exc


def install(destination: Path, *, fetch: callable | None = None) -> dict[str, str]:
    if fetch is None:
        fetch = _fetch
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
        url = base + filename
        _ensure_archive(archive, url, expected, filename, fetch)
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
