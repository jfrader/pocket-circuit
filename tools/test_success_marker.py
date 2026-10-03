#!/usr/bin/env python3
"""Discover a Godot test's completion marker and optional fixed simulation clock."""

import argparse
from pathlib import Path
import re


PATTERN = re.compile(r'^\s*print\(\s*"([A-Z][A-Z0-9_]*(?:_TEST|_QA|_BENCHMARK|_HARNESS) PASS)(?:[" ])', re.MULTILINE)
FIXED_FPS_DECLARATION = re.compile(r'^\s*const FIXED_FPS\b[^\n]*', re.MULTILINE)
FIXED_FPS_VALUE = re.compile(r'\s*const FIXED_FPS\s*:=\s*([0-9]+)\s*(?:#.*)?')


def marker_for(path: Path) -> str:
    markers = set(PATTERN.findall(path.read_text(encoding="utf-8")))
    if len(markers) != 1:
        raise ValueError(f"{path.name} must declare one literal <NAME>_TEST/QA/BENCHMARK/HARNESS PASS completion marker")
    return markers.pop()


def fixed_fps_for(path: Path) -> int | None:
    declarations = FIXED_FPS_DECLARATION.findall(path.read_text(encoding="utf-8"))
    if not declarations:
        return None
    if len(declarations) == 1:
        match = FIXED_FPS_VALUE.fullmatch(declarations[0])
        if match and int(match[1]) > 0:
            return int(match[1])
    raise ValueError(f"{path.name} FIXED_FPS must be one positive integer literal")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test", type=Path)
    parser.add_argument("--fixed-fps", action="store_true")
    args = parser.parse_args()
    try:
        if args.fixed_fps:
            fps = fixed_fps_for(args.test)
            if fps is not None:
                print(fps)
        else:
            print(marker_for(args.test))
    except ValueError as error:
        raise SystemExit(str(error)) from error
