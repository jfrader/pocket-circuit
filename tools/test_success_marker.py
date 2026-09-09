#!/usr/bin/env python3
"""Discover the single literal completion marker required from a Godot test."""

from pathlib import Path
import re
import sys


PATTERN = re.compile(r'^\s*print\(\s*"([A-Z][A-Z0-9_]*(?:_TEST|_QA|_BENCHMARK|_HARNESS) PASS)(?:[" ])', re.MULTILINE)


def marker_for(path: Path) -> str:
    markers = set(PATTERN.findall(path.read_text(encoding="utf-8")))
    if len(markers) != 1:
        raise ValueError(f"{path.name} must declare one literal <NAME>_TEST/QA/BENCHMARK/HARNESS PASS completion marker")
    return markers.pop()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: test_success_marker.py TEST.gd")
    try:
        print(marker_for(Path(sys.argv[1])))
    except ValueError as error:
        raise SystemExit(str(error)) from error
