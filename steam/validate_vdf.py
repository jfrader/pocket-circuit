#!/usr/bin/env python3
"""Validate Pocket Circuit's completed SteamPipe KeyValues files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


class VDFError(ValueError):
    pass


def tokenize(text: str) -> list[str]:
    tokens: list[str] = []
    index = 0
    while index < len(text):
        character = text[index]
        if character.isspace():
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = len(text) if newline < 0 else newline + 1
            continue
        if character in "{}":
            tokens.append(character)
            index += 1
            continue
        if character == '"':
            index += 1
            value: list[str] = []
            while index < len(text) and text[index] != '"':
                if text[index] == "\\":
                    index += 1
                    if index >= len(text):
                        raise VDFError("unterminated escape sequence")
                value.append(text[index])
                index += 1
            if index >= len(text):
                raise VDFError("unterminated quoted string")
            tokens.append("".join(value))
            index += 1
            continue
        end = index
        while end < len(text) and not text[end].isspace() and text[end] not in '{}"':
            end += 1
        if end == index:
            raise VDFError(f"unexpected character at offset {index}")
        tokens.append(text[index:end])
        index = end
    return tokens


def parse_pairs(tokens: list[str], index: int = 0, nested: bool = False) -> tuple[list[tuple[str, object]], int]:
    pairs: list[tuple[str, object]] = []
    while index < len(tokens):
        if tokens[index] == "}":
            if not nested:
                raise VDFError("unexpected closing brace")
            return pairs, index + 1
        key = tokens[index]
        if key == "{":
            raise VDFError("object is missing a key")
        index += 1
        if index >= len(tokens):
            raise VDFError(f"key {key!r} is missing a value")
        if tokens[index] == "{":
            value, index = parse_pairs(tokens, index + 1, True)
        elif tokens[index] == "}":
            raise VDFError(f"key {key!r} is missing a value")
        else:
            value = tokens[index]
            index += 1
        pairs.append((key, value))
    if nested:
        raise VDFError("unterminated object")
    return pairs, index


def as_object(value: object, path: str) -> dict[str, object]:
    if not isinstance(value, list):
        raise VDFError(f"{path} must be an object")
    parsed: dict[str, object] = {}
    original_keys: dict[str, str] = {}
    for key, child in value:
        normalized = key.casefold()
        if normalized in parsed:
            raise VDFError(f"{path} contains duplicate key {key!r}")
        parsed[normalized] = child
        original_keys[normalized] = key
    return parsed


def required_value(obj: dict[str, object], key: str, path: str) -> object:
    normalized = key.casefold()
    if normalized not in obj:
        raise VDFError(f"{path} is missing {key!r}")
    return obj[normalized]


def load_object(path: Path) -> dict[str, object]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise VDFError(f"could not read {path}: {error}") from error
    tokens = tokenize(text)
    pairs, final_index = parse_pairs(tokens)
    if final_index != len(tokens):
        raise VDFError(f"could not parse all of {path}")
    return as_object(pairs, str(path))


def validate_depot(path: Path, expected_id: str) -> None:
    root = load_object(path)
    config = as_object(required_value(root, "DepotBuildConfig", str(path)), f"{path}:DepotBuildConfig")
    depot_id = required_value(config, "DepotID", f"{path}:DepotBuildConfig")
    if not isinstance(depot_id, str) or depot_id != expected_id:
        raise VDFError(f"{path}:DepotBuildConfig.DepotID must be {expected_id!r}")


def validate_app(
    path: Path,
    app_id: str,
    windows_depot_id: str,
    linux_depot_id: str,
    windows_config: Path,
    linux_config: Path,
) -> None:
    root = load_object(path)
    app = as_object(required_value(root, "appbuild", str(path)), f"{path}:appbuild")
    actual_app_id = required_value(app, "appid", f"{path}:appbuild")
    if not isinstance(actual_app_id, str) or actual_app_id != app_id:
        raise VDFError(f"{path}:appbuild.appid must be {app_id!r}")
    depots = as_object(required_value(app, "depots", f"{path}:appbuild"), f"{path}:appbuild.depots")
    expected = {
        windows_depot_id: str(windows_config.resolve()),
        linux_depot_id: str(linux_config.resolve()),
    }
    if set(depots) != set(expected):
        raise VDFError(f"{path}:appbuild.depots must contain exactly {sorted(expected)}")
    for depot_id, expected_path in expected.items():
        actual_path = depots[depot_id]
        if not isinstance(actual_path, str) or actual_path != expected_path:
            raise VDFError(f"{path}:appbuild.depots.{depot_id} must be {expected_path!r}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-config", type=Path, required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--windows-depot-id", required=True)
    parser.add_argument("--linux-depot-id", required=True)
    parser.add_argument("--windows-config", type=Path, required=True)
    parser.add_argument("--linux-config", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        validate_app(
            args.app_config,
            args.app_id,
            args.windows_depot_id,
            args.linux_depot_id,
            args.windows_config,
            args.linux_config,
        )
        validate_depot(args.windows_config, args.windows_depot_id)
        validate_depot(args.linux_config, args.linux_depot_id)
    except VDFError as error:
        print(f"STEAM_VDF FAIL: {error}", file=sys.stderr)
        return 1
    print("STEAM_VDF PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
