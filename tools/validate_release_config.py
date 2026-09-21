#!/usr/bin/env python3
"""Validate release presets and repository packaging guardrails."""

from __future__ import annotations

import configparser
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_EXCLUSIONS = {
    "assets/source/**",
    "assets/ui/concepts/**",
    "addons/godot_mcp/**",
    "addons/release_export/**",
    "builds/**",
    "tests/**",
    "tools/**",
    "server/**",
    "docs/**",
    "steam/**",
    "media/**",
    "runlogs/**",
    "scripts/ui/debug_overlay.gd",
}
EXPECTED_PRESETS = {
    "Linux x86_64": {
        "platform": "Linux",
        "export_path": "builds/linux/pocket-circuit.x86_64",
    },
    "Windows Desktop x86_64": {
        "platform": "Windows Desktop",
        "export_path": "builds/windows/pocket-circuit.exe",
    },
}
EXPECTED_STEAM_FILES = {
    "app_build_example.vdf": {
        "<STEAM_APP_ID>",
        "<WINDOWS_DEPOT_ID>",
        "<LINUX_DEPOT_ID>",
        "<CONTENT_ROOT>",
        "<WINDOWS_DEPOT_CONFIG>",
        "<LINUX_DEPOT_CONFIG>",
    },
    "depot_build_windows_example.vdf": {"<WINDOWS_DEPOT_ID>", "<CONTENT_ROOT>"},
    "depot_build_linux_example.vdf": {"<LINUX_DEPOT_ID>", "<CONTENT_ROOT>"},
}
REQUIRED_RELEASE_NOTICES = {
    "ASSET_PROVENANCE.md",
    "THIRD_PARTY_NOTICES.md",
    "assets/**/LICENSE*",
    "data/vendor/**/LICENSE*",
    "data/vendor/procedural_2d/*.json",
}
EXPECTED_GAMESTRUMENTS_VENDOR_FILES = {
    "LICENSE.md",
    "README.md",
    "bin/gamestruments_godot.dll",
    "bin/libgamestruments_godot.so",
    "gamestruments.gdextension",
}
EXPECTED_STEAM_MEDIA = {
    "capsules/community_icon.png": (184, 184),
    "capsules/header_capsule.png": (920, 430),
    "capsules/library_capsule.png": (600, 900),
    "capsules/library_hero.png": (3840, 1240),
    "capsules/library_logo.png": (1280, 720),
    "capsules/main_capsule.png": (1232, 706),
    "capsules/page_background.png": (1438, 810),
    "capsules/small_capsule.png": (462, 174),
    "capsules/vertical_capsule.png": (748, 896),
    "screenshots/01_title.png": (1920, 1080),
    "screenshots/02_championship_map.png": (1920, 1080),
    "screenshots/03_kitchen_briefing.png": (1920, 1080),
    "screenshots/04_vehicle_select.png": (1920, 1080),
    "screenshots/05_kitchen_race.png": (1920, 1080),
    "screenshots/06_workshop_race.png": (1920, 1080),
    "screenshots/07_office_race.png": (1920, 1080),
    "trailer/opening_card.png": (1920, 1080),
    "trailer/ending_card.png": (1920, 1080),
}


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def validate_upload_wrapper(upload_wrapper: Path, errors: list[str]) -> None:
    with tempfile.TemporaryDirectory(prefix="pocket-circuit-steam-wrapper-") as temporary:
        temporary_path = Path(temporary)
        fake_steamcmd = temporary_path / "steamcmd"
        fake_steamcmd.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        fake_steamcmd.chmod(0o700)

        windows_config = temporary_path / "windows depot.vdf"
        linux_config = temporary_path / "linux depot.vdf"
        windows_config.write_text('"DepotBuildConfig" { "DepotID" "1001" }\n', encoding="utf-8")
        linux_config.write_text('"DepotBuildConfig" { "DepotID" "1002" }\n', encoding="utf-8")
        app_config = temporary_path / "app build.vdf"
        app_config.write_text(
            '"appbuild"\n{\n'
            '  "appid" "1000"\n'
            '  "depots"\n  {\n'
            f'    "1001" "{windows_config.resolve()}"\n'
            f'    "1002"   "{linux_config.resolve()}"\n'
            '  }\n}\n',
            encoding="utf-8",
        )

        def run_wrapper() -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                [
                    str(upload_wrapper),
                    "--upload",
                    "--steamcmd",
                    str(fake_steamcmd),
                    "--account",
                    "release-validation",
                    "--app-id",
                    "1000",
                    "--windows-depot-id",
                    "1001",
                    "--linux-depot-id",
                    "1002",
                    "--config",
                    str(app_config),
                    "--windows-config",
                    str(windows_config),
                    "--linux-config",
                    str(linux_config),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=10,
            )

        result = run_wrapper()
        if result.returncode != 0:
            output = (result.stderr or result.stdout).strip()
            errors.append(f"Steam upload wrapper rejected a valid multi-space depot mapping: {output}")

        wrong_windows_path = temporary_path / "decoy windows.vdf"
        app_config.write_text(
            '"appbuild"\n{\n'
            '  "appid" "1000"\n'
            '  "depots"\n  {\n'
            f'    "1001" "{wrong_windows_path.resolve()}"\n'
            f'    "1002" "{linux_config.resolve()}"\n'
            '  }\n'
            f'  "decoy" {{ "1001" "{windows_config.resolve()}" }}\n'
            '}\n',
            encoding="utf-8",
        )
        if run_wrapper().returncode == 0:
            errors.append("Steam upload wrapper accepted a valid-looking depot mapping outside appbuild.depots")

        app_config.write_text(
            '"appbuild"\n{\n'
            '  "appid" "1000"\n'
            '  "depots"\n  {\n'
            f'    "1001" "{windows_config.resolve()}"\n'
            f'    "1001" "{windows_config.resolve()}"\n'
            f'    "1002" "{linux_config.resolve()}"\n'
            '  }\n}\n',
            encoding="utf-8",
        )
        if run_wrapper().returncode == 0:
            errors.append("Steam upload wrapper accepted a duplicate depot mapping")


def png_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        offset = 8
        dimensions: tuple[int, int] | None = None
        compressed_image = bytearray()
        reached_end = False
        while offset + 12 <= len(data):
            length = struct.unpack(">I", data[offset : offset + 4])[0]
            chunk_type = data[offset + 4 : offset + 8]
            chunk_end = offset + 12 + length
            if chunk_end > len(data):
                return None
            chunk_data = data[offset + 8 : offset + 8 + length]
            expected_crc = struct.unpack(">I", data[offset + 8 + length : chunk_end])[0]
            actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
            if actual_crc != expected_crc:
                return None
            if chunk_type == b"IHDR":
                if length != 13 or dimensions is not None:
                    return None
                dimensions = struct.unpack(">II", chunk_data[:8])
            elif chunk_type == b"IDAT":
                compressed_image.extend(chunk_data)
            elif chunk_type == b"IEND":
                reached_end = True
                if chunk_end != len(data):
                    return None
                break
            offset = chunk_end
        if dimensions is None or not compressed_image or not reached_end:
            return None
        if not zlib.decompress(compressed_image):
            return None
        return dimensions
    except (OSError, struct.error, zlib.error):
        return None


def png_decodes(path: Path) -> bool:
    decoder = shutil.which("magick") or shutil.which("convert")
    if decoder is None:
        return False
    try:
        result = subprocess.run(
            [decoder, str(path), "null:"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def validate_png_decoder(errors: list[str]) -> None:
    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        checksum = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", checksum)

    malformed = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"not pixel scanlines"))
        + chunk(b"IEND", b"")
    )
    with tempfile.TemporaryDirectory(prefix="pocket-circuit-png-validation-") as temporary_dir:
        malformed_path = Path(temporary_dir) / "malformed.png"
        malformed_path.write_bytes(malformed)
        if png_decodes(malformed_path):
            errors.append("Steam media decoder accepted a malformed PNG pixel stream")


def validate_media_integrity(media_root: Path, errors: list[str]) -> None:
    checksum_path = media_root / "SHA256SUMS"
    if checksum_path.is_file():
        result = subprocess.run(
            ["sha256sum", "--check", "SHA256SUMS"],
            cwd=media_root,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            errors.append(f"Steam media checksum verification failed: {(result.stderr or result.stdout).strip()}")

    trailer_path = media_root / "trailer" / "pocket_circuit_gameplay_trailer.mp4"
    if not trailer_path.is_file():
        return
    try:
        probe = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration:stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,sample_rate,channels,bit_rate",
                "-of",
                "json",
                str(trailer_path),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        details = json.loads(probe.stdout)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        errors.append(f"could not inspect Steam trailer encoding with ffprobe: {error}")
        return
    video_streams = [stream for stream in details.get("streams", []) if stream.get("codec_type") == "video"]
    audio_streams = [stream for stream in details.get("streams", []) if stream.get("codec_type") == "audio"]
    if len(video_streams) != 1 or len(audio_streams) != 1:
        errors.append("Steam trailer must contain exactly one video stream and one audio stream")
        return
    video = video_streams[0]
    audio = audio_streams[0]
    expected_video = {
        "codec_name": "h264",
        "width": 1920,
        "height": 1080,
        "pix_fmt": "yuv420p",
        "r_frame_rate": "30/1",
    }
    for field, expected in expected_video.items():
        if video.get(field) != expected:
            errors.append(f"Steam trailer {field} must be {expected!r}, found {video.get(field)!r}")
    try:
        video_bitrate = int(video["bit_rate"])
    except (KeyError, TypeError, ValueError):
        errors.append("Steam trailer video bitrate could not be read")
    else:
        if video_bitrate < 5_000_000:
            errors.append(f"Steam trailer video bitrate must be at least 5000000, found {video_bitrate}")
    if audio.get("codec_name") != "aac":
        errors.append(f"Steam trailer audio codec must be 'aac', found {audio.get('codec_name')!r}")
    if audio.get("sample_rate") != "48000":
        errors.append(f"Steam trailer audio sample rate must be '48000', found {audio.get('sample_rate')!r}")
    if audio.get("channels") != 2:
        errors.append(f"Steam trailer audio must have 2 channels, found {audio.get('channels')!r}")
    try:
        audio_bitrate = int(audio["bit_rate"])
    except (KeyError, TypeError, ValueError):
        errors.append("Steam trailer audio bitrate could not be read")
    else:
        if audio_bitrate < 160_000:
            errors.append(f"Steam trailer audio bitrate must be at least 160000, found {audio_bitrate}")
    try:
        duration = float(details["format"]["duration"])
    except (KeyError, TypeError, ValueError):
        errors.append("Steam trailer duration could not be read")
    else:
        if not 24.9 <= duration <= 25.1:
            errors.append(f"Steam trailer duration must be 25 seconds, found {duration:.3f}")


def main() -> int:
    errors: list[str] = []

    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
    active_ignores = {line.strip() for line in gitignore if line.strip() and not line.lstrip().startswith("#")}
    if "export_presets.cfg" in active_ignores or "/export_presets.cfg" in active_ignores:
        errors.append("export_presets.cfg must be tracked, not ignored")
    if "/builds/" not in active_ignores:
        errors.append("/builds/ must remain ignored")

    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    if not re.search(r'^config/version="1\.0\.0"$', project_text, re.MULTILINE):
        errors.append("project.godot must set config/version to 1.0.0")
    icon_path = ROOT / "assets/branding/pocket_circuit_icon.svg"
    if not re.search(r'^config/icon="res://assets/branding/pocket_circuit_icon\.svg"$', project_text, re.MULTILINE):
        errors.append("project.godot must use the Pocket Circuit branding icon")
    if not icon_path.is_file():
        errors.append("project icon file is missing")
    else:
        icon_text = icon_path.read_text(encoding="utf-8").lower()
        external_reference = re.search(r'(?:href|xlink:href)\s*=\s*["\']https?://', icon_text)
        if "<script" in icon_text or external_reference:
            errors.append("project icon must not contain scripts or external references")
    release_plugin_paths = [
        ROOT / "addons/release_export/plugin.cfg",
        ROOT / "addons/release_export/plugin.gd",
        ROOT / "addons/release_export/release_export_plugin.gd",
    ]
    if '"res://addons/release_export/plugin.cfg"' not in project_text:
        errors.append("release export plugin must be enabled")
    if '"res://addons/godot_mcp/plugin.cfg"' in project_text or re.search(r"^MCPRuntime=", project_text, re.MULTILINE):
        errors.append("local Godot MCP plugin/autoload entries must be removed before release")
    for plugin_path in release_plugin_paths:
        if not plugin_path.is_file():
            errors.append(f"missing release export plugin file: {plugin_path.relative_to(ROOT)}")
    release_plugin_text = release_plugin_paths[-1].read_text(encoding="utf-8") if release_plugin_paths[-1].is_file() else ""
    if 'scene.get_node_or_null("DebugOverlay")' not in release_plugin_text or "debug_overlay.free()" not in release_plugin_text:
        errors.append("release export plugin must strip the DebugOverlay node")

    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    try:
        parser.read(ROOT / "export_presets.cfg", encoding="utf-8")
    except (configparser.Error, OSError) as error:
        errors.append(f"could not parse export_presets.cfg: {error}")

    presets: dict[str, tuple[configparser.SectionProxy, configparser.SectionProxy]] = {}
    for section_name in parser.sections():
        match = re.fullmatch(r"preset\.(\d+)", section_name)
        if not match:
            continue
        options_name = f"{section_name}.options"
        if options_name not in parser:
            errors.append(f"{section_name} has no options section")
            continue
        name = unquote(parser[section_name].get("name", ""))
        presets[name] = (parser[section_name], parser[options_name])

    if set(presets) != set(EXPECTED_PRESETS):
        errors.append(f"release preset names must be exactly: {', '.join(EXPECTED_PRESETS)}")

    for name, expected in EXPECTED_PRESETS.items():
        if name not in presets:
            continue
        preset, options = presets[name]
        for field, expected_value in expected.items():
            actual = unquote(preset.get(field, ""))
            if actual != expected_value:
                errors.append(f"{name}: {field} must be {expected_value!r}, found {actual!r}")
        if unquote(preset.get("export_filter", "")) != "all_resources":
            errors.append(f"{name}: export_filter must keep all game resources")
        include_filter = {item.strip() for item in unquote(preset.get("include_filter", "")).split(",") if item.strip()}
        if not REQUIRED_RELEASE_NOTICES.issubset(include_filter):
            errors.append(f"{name}: runtime license notices are not included")
        exclusions = {item.strip() for item in unquote(preset.get("exclude_filter", "")).split(",") if item.strip()}
        missing = REQUIRED_EXCLUSIONS - exclusions
        if missing:
            errors.append(f"{name}: missing exclusions: {', '.join(sorted(missing))}")
        if preset.get("script_export_mode", "").strip() != "2":
            errors.append(f"{name}: release scripts must be compiled with script_export_mode=2")
        if unquote(options.get("binary_format/embed_pck", "")) != "false":
            errors.append(f"{name}: embedded PCK must be disabled")
        if unquote(options.get("binary_format/architecture", "")) != "x86_64":
            errors.append(f"{name}: architecture must be x86_64")

    windows = presets.get("Windows Desktop x86_64")
    if windows:
        _, options = windows
        expected_metadata = {
            "application/file_version": "1.0.0.0",
            "application/product_version": "1.0.0.0",
            "application/company_name": "Gurisitos Games",
            "application/product_name": "Pocket Circuit",
        }
        for field, expected_value in expected_metadata.items():
            if unquote(options.get(field, "")) != expected_value:
                errors.append(f"Windows Desktop x86_64: {field} must be {expected_value!r}")
        if unquote(options.get("codesign/enable", "")) != "false":
            errors.append("Windows code signing must stay disabled until owner credentials are supplied outside the repository")

    for filename, placeholders in EXPECTED_STEAM_FILES.items():
        path = ROOT / "steam" / filename
        if not path.is_file():
            errors.append(f"missing Steam example config: steam/{filename}")
            continue
        text = path.read_text(encoding="utf-8")
        for placeholder in placeholders:
            if placeholder not in text:
                errors.append(f"steam/{filename} must retain placeholder {placeholder}")
        if re.search(r'(?i)"(?:appid|depotid)"\s+"[0-9]+"', text):
            errors.append(f"steam/{filename} contains a real-looking numeric Steam ID")
        if re.search(r"(?i)password|passwd|secret|access[_-]?token", text):
            errors.append(f"steam/{filename} contains a credential-like field")

    upload_wrapper = ROOT / "steam/upload_build.sh"
    if not upload_wrapper.is_file():
        errors.append("missing Steam upload wrapper")
    else:
        wrapper_text = upload_wrapper.read_text(encoding="utf-8")
        for guard in ("--upload", "<STEAM_APP_ID>", "<WINDOWS_DEPOT_ID>", "<LINUX_DEPOT_ID>", "<CONTENT_ROOT>", "<WINDOWS_DEPOT_CONFIG>", "<LINUX_DEPOT_CONFIG>"):
            if guard not in wrapper_text:
                errors.append(f"Steam upload wrapper is missing guard {guard}")
        validate_upload_wrapper(upload_wrapper, errors)
    if not (ROOT / "steam/validate_vdf.py").is_file():
        errors.append("missing structural Steam VDF validator")

    for notice_path in (
        ROOT / "THIRD_PARTY_NOTICES.md",
        ROOT / "ASSET_PROVENANCE.md",
        ROOT / "assets/audio/LICENSE.md",
        ROOT / "data/vendor/procedural_2d/LICENSE",
    ):
        if not notice_path.is_file():
            errors.append(f"missing release notice: {notice_path.relative_to(ROOT)}")

    gamestruments_vendor = ROOT / "vendor/gamestruments"
    actual_vendor_files = {
        path.relative_to(gamestruments_vendor).as_posix()
        for path in gamestruments_vendor.rglob("*")
        if path.is_file()
    }
    if actual_vendor_files != EXPECTED_GAMESTRUMENTS_VENDOR_FILES:
        missing = sorted(EXPECTED_GAMESTRUMENTS_VENDOR_FILES - actual_vendor_files)
        unexpected = sorted(actual_vendor_files - EXPECTED_GAMESTRUMENTS_VENDOR_FILES)
        errors.append(f"Gamestruments vendor contents differ (missing={missing}, unexpected={unexpected})")
    if not (ROOT / "vendor/.gdignore").is_file():
        errors.append("vendor/.gdignore must prevent Godot from loading the vendored descriptor beside the synced addon")
    vendor_readme = gamestruments_vendor / "README.md"
    if vendor_readme.is_file():
        readme_text = vendor_readme.read_text(encoding="utf-8")
        for required_text in ("v1.0.3", "credential-free", "fine-grained GitHub PAT", "Contents: read"):
            if required_text not in readme_text:
                errors.append(f"vendor/gamestruments/README.md must document {required_text}")

    media_root = ROOT / "media" / "steam"
    validate_png_decoder(errors)
    for relative_path, expected_dimensions in EXPECTED_STEAM_MEDIA.items():
        path = media_root / relative_path
        if not path.is_file():
            errors.append(f"missing Steam media: media/steam/{relative_path}")
            continue
        dimensions = png_dimensions(path)
        if dimensions != expected_dimensions:
            errors.append(
                f"media/steam/{relative_path} must be {expected_dimensions[0]}x{expected_dimensions[1]} PNG, found {dimensions}"
            )
        elif not png_decodes(path):
            errors.append(f"Steam media image cannot be fully decoded: media/steam/{relative_path}")
    for relative_path in ("BUILD_SHA256SUMS", "MANIFEST.md", "SHA256SUMS"):
        if not (media_root / relative_path).is_file():
            errors.append(f"missing Steam media evidence: media/steam/{relative_path}")
    trailer_path = media_root / "trailer" / "pocket_circuit_gameplay_trailer.mp4"
    if not trailer_path.is_file() or trailer_path.stat().st_size < 1_000_000:
        errors.append("Steam gameplay trailer is missing or unexpectedly small")
    elif b"ftyp" not in trailer_path.read_bytes()[:64]:
        errors.append("Steam gameplay trailer is not a recognized MP4 container")
    validate_media_integrity(media_root, errors)

    try:
        tracked_output = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=ROOT,
            check=True,
            capture_output=True,
        ).stdout.decode("utf-8").split("\0")
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        errors.append(f"could not inspect tracked files: {error}")
    else:
        tracked_builds = [path for path in tracked_output if path.startswith("builds/")]
        if tracked_builds:
            errors.append(f"build artifacts are tracked: {', '.join(tracked_builds)}")

    if errors:
        for error in errors:
            print(f"RELEASE_CONFIG FAIL: {error}", file=sys.stderr)
        return 1
    print("RELEASE_CONFIG PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
