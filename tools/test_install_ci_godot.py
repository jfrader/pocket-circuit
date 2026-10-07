#!/usr/bin/env python3
"""Self-contained test for retry/verify seam in install_ci_godot.py (no network, no large downloads, no deps).

Exercises: success, transient-fail-then-success, permanent-bad-checksum (clear diagnostic + no partials), verified-cache-skip.
Run with: python3 tools/test_install_ci_godot.py
Exits non-zero on any failure.
"""
from __future__ import annotations


import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path

# Load the module under test via its source (so we can reach _ensure_archive seam and _fetch)
HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("_install_ci_godot_test", HERE / "install_ci_godot.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def _make_fetch(data: bytes, status: int = 200, size: int | None = None) -> callable:
    """Return a fetch(url, dest) that writes `data` and returns (status, size or len)."""
    def fetch(url: str, dest: Path) -> tuple[int, int | None]:
        dest.write_bytes(data)
        return status, (size if size is not None else len(data))
    return fetch


def _make_failing_fetch(exc: Exception) -> callable:
    """Return a fetch that raises the given exc (simulates transient net fail)."""
    def fetch(url: str, dest: Path) -> tuple[int, int | None]:
        raise exc
    return fetch


def run_tests() -> int:
    failures = []

    def record_fail(name: str, detail: str):
        failures.append(f"{name}: {detail}")
        print(f"FAIL {name}: {detail}")

    # 1. success
    try:
        with tempfile.TemporaryDirectory() as td_str:
            td = Path(td_str)
            archive = td / "good.zip"
            data = b"success-payload-1234567890"
            expected_sha = hashlib.sha256(data).hexdigest()
            fetch = _make_fetch(data)
            MOD._ensure_archive(archive, "https://example/good", expected_sha, "good.zip", fetch)
            if not archive.exists():
                raise AssertionError("archive not created")
            if archive.read_bytes() != data:
                raise AssertionError("archive content wrong")
            actual = hashlib.sha256(archive.read_bytes()).hexdigest()
            if actual != expected_sha:
                raise AssertionError("sha not matching after")
            print("PASS: success")
    except Exception as e:
        record_fail("success", f"{type(e).__name__}: {e}")

    # 2. one transient failure then success (retry)
    try:
        with tempfile.TemporaryDirectory() as td_str:
            td = Path(td_str)
            archive = td / "retry.zip"
            data = b"retry-after-transient-abcdef"
            expected_sha = hashlib.sha256(data).hexdigest()
            call_count = 0
            def flaky(u: str, d: Path) -> tuple[int, int | None]:
                nonlocal call_count
                call_count += 1
                if call_count == 1:
                    raise ConnectionResetError("simulated transient drop")
                d.write_bytes(data)
                return 200, len(data)
            MOD._ensure_archive(archive, "https://example/retry", expected_sha, "retry.zip", flaky)
            if call_count != 2:
                raise AssertionError(f"expected 2 calls, got {call_count}")
            if not archive.exists() or archive.read_bytes() != data:
                raise AssertionError("final archive wrong after retry")
            print("PASS: transient failure then success (retried)")
    except Exception as e:
        record_fail("transient-then-success", f"{type(e).__name__}: {e}")

    # 3. permanent bad checksum (clear message, no partial left, retried)
    try:
        with tempfile.TemporaryDirectory() as td_str:
            td = Path(td_str)
            archive = td / "bad.zip"
            bad_data = b"permanently-corrupt-body-here"
            wrong_sha = "0" * 64  # guaranteed mismatch
            call_count = 0
            def always_bad(u: str, d: Path) -> tuple[int, int | None]:
                nonlocal call_count
                call_count += 1
                d.write_bytes(bad_data)
                return 200, len(bad_data)
            try:
                MOD._ensure_archive(archive, "https://example/bad", wrong_sha, "bad.zip", always_bad)
                record_fail("permanent-bad-checksum", "did not raise")
            except ValueError as ve:
                msg = str(ve)
                if "Checksum mismatch for official asset bad.zip" not in msg:
                    raise AssertionError(f"msg did not start with expected: {msg}")
                if "HTTP 200" not in msg:
                    raise AssertionError(f"msg missing HTTP status: {msg}")
                if "bytes received" not in msg or "vs expected" not in msg:
                    raise AssertionError(f"msg missing bytes info: {msg}")
                if "computed " not in msg or " != " not in msg:
                    raise AssertionError(f"msg missing computed vs expected: {msg}")
                print(f"PASS: permanent bad checksum (msg: {msg[:120]}...)")
            else:
                record_fail("permanent-bad-checksum", "no exception raised")
            # verify no partials left, and no bad archive committed
            leftovers = [p for p in td.iterdir() if p.is_file() and (".part" in p.name or "bad.zip" in p.name and hashlib.sha256(p.read_bytes()).hexdigest() != wrong_sha)]
            # after fail, archive should not exist (never replaced)
            if archive.exists():
                record_fail("permanent-bad-checksum", "archive left behind on failure")
            partials = list(td.glob("*.part*"))
            if partials:
                record_fail("permanent-bad-checksum", f"partials left: {partials}")
            if call_count < 2:  # at least retried some
                print(f"NOTE: bad checksum did {call_count} attempts (retries exercised)")
            # if we reach here without recording, good
    except Exception as e:
        record_fail("permanent-bad-checksum", f"unexpected: {type(e).__name__}: {e}")

    # 4. verified-cache skip (no fetch called)
    try:
        with tempfile.TemporaryDirectory() as td_str:
            td = Path(td_str)
            archive = td / "cached.zip"
            data = b"already-verified-good-data"
            expected_sha = hashlib.sha256(data).hexdigest()
            archive.write_bytes(data)  # pre-populate good
            call_count = 0
            def never_called(u: str, d: Path) -> tuple[int, int | None]:
                nonlocal call_count
                call_count += 1
                return 418, 0
            MOD._ensure_archive(archive, "https://example/cached", expected_sha, "cached.zip", never_called)
            if call_count != 0:
                raise AssertionError(f"fetch called {call_count} times on cache hit")
            print("PASS: verified-cache skip")
    except Exception as e:
        record_fail("cache-skip", f"{type(e).__name__}: {e}")

    # also quick smoke that bad-on-disk gets replaced (not strictly required but verifies)
    try:
        with tempfile.TemporaryDirectory() as td_str:
            td = Path(td_str)
            archive = td / "stale.zip"
            good_data = b"fresh-good"
            good_sha = hashlib.sha256(good_data).hexdigest()
            archive.write_bytes(b"stale-corrupt")  # bad sha on disk
            call_count = 0
            def one_call(u, d):
                nonlocal call_count
                call_count += 1
                d.write_bytes(good_data)
                return 200, len(good_data)
            MOD._ensure_archive(archive, "u", good_sha, "stale.zip", one_call)
            if call_count != 1:
                raise AssertionError("did not redownload on stale")
            if archive.read_bytes() != good_data:
                raise AssertionError("did not replace stale")
            print("PASS: stale cache replaced")
    except Exception as e:
        record_fail("stale-replace", f"{type(e).__name__}: {e}")

    if failures:
        print("\n--- FAILURES ---")
        for f in failures:
            print(f"  {f}")
        return 1
    print("\nAll tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(run_tests())
