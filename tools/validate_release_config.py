#!/usr/bin/env python3
"""Validate release presets and repository packaging guardrails."""

from __future__ import annotations

import configparser
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_EXCLUSIONS = {
    "addons/godot_mcp/**",
    "addons/release_export/**",
    "builds/**",
    "tests/**",
    "tools/**",
    "server/**",
    "docs/**",
    "steam/**",
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


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


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
        if not {"THIRD_PARTY_NOTICES.md", "assets/**/LICENSE*"}.issubset(include_filter):
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
