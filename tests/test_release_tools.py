from pathlib import Path
from contextlib import contextmanager
import json
import mmap
import os
import select
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from test_success_marker import fixed_fps_for, marker_for
from validate_release_config import validate_gamestruments_readme


class CompletionMarkerTests(unittest.TestCase):
    def test_each_script_has_one_completion_marker(self):
        for path in sorted((ROOT / "tests").glob("*.gd")):
            with self.subTest(test=path.name):
                self.assertTrue(marker_for(path).endswith(" PASS"))

    def test_intermediate_and_commented_markers_do_not_count(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.gd"
            path.write_text('# print("IGNORED_TEST PASS")\nprint("GATE PASS intermediate")\nprint("REAL_TEST PASS details")\n')
            self.assertEqual(marker_for(path), "REAL_TEST PASS")
            path.write_text('print("GATE PASS intermediate")\n')
            with self.assertRaises(ValueError):
                marker_for(path)

    def test_ambiguous_markers_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.gd"
            path.write_text('print("ONE_TEST PASS")\nprint("TWO_TEST PASS")\n')
            with self.assertRaises(ValueError):
                marker_for(path)


class FixedClockTests(unittest.TestCase):
    def test_clock_is_opt_in(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.gd"
            path.write_text('extends SceneTree\n# const FIXED_FPS := 60\n')
            self.assertIsNone(fixed_fps_for(path))
            path.write_text('extends SceneTree\nconst FIXED_FPS := 60 # physics clock\n')
            self.assertEqual(fixed_fps_for(path), 60)

    def test_invalid_clock_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.gd"
            for declaration in (
                'const FIXED_FPS := 0\n',
                'const FIXED_FPS := -60\n',
                'const FIXED_FPS := 60.0\n',
                'const FIXED_FPS := 30 + 30\n',
                'const FIXED_FPS := 60\nconst FIXED_FPS := 30\n',
            ):
                with self.subTest(declaration=declaration):
                    path.write_text(declaration)
                    with self.assertRaises(ValueError):
                        fixed_fps_for(path)


class AudioDocumentationTests(unittest.TestCase):
    def test_recorded_audio_has_one_shipped_provenance_entry(self):
        provenance = (ROOT / "ASSET_PROVENANCE.md").read_text()
        shipped = provenance.split("## Shipped asset groups", 1)[1].split("\n## ", 1)[0]
        for path in sorted((ROOT / "assets/audio").iterdir()):
            if path.suffix not in {".ogg", ".wav", ".mp3"}:
                continue
            with self.subTest(asset=path.name):
                row_prefix = f"| `{path.relative_to(ROOT).as_posix()}` |"
                rows = [line for line in shipped.splitlines() if line.startswith(row_prefix)]
                self.assertEqual(len(rows), 1, "A shipped recording must have one unambiguous source")


class GodotGateTests(unittest.TestCase):
    def run_source_worker(self, declaration):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tests").mkdir()
            (root / "tools").mkdir()
            shutil.copyfile(ROOT / "tools/test_success_marker.py", root / "tools/test_success_marker.py")
            (root / "tests/fixture.gd").write_text(declaration + '\nprint("FIXTURE_TEST PASS")\n')
            fake_godot = root / "godot"
            fake_godot.write_text(
                '#!/usr/bin/env python3\nimport json,sys\n'
                'print(json.dumps(sys.argv[1:]))\nprint("FIXTURE_TEST PASS")\n'
            )
            fake_godot.chmod(0o755)
            return subprocess.run(
                ["bash", "-c", 'source "$1"; export -f run_godot_checked run_godot_test_checked; shift; bash -c \'run_godot_test_checked "$@"\' worker "$@"',
                 "gate-test", str(ROOT / "tools/godot_gate.sh"), str(root), str(fake_godot), "tests/fixture.gd"],
                capture_output=True, text=True, timeout=10,
            )

    def test_source_worker_applies_only_declared_clock(self):
        for declaration, clock_args in (("", []), ("const FIXED_FPS := 60", ["--fixed-fps", "60"])):
            with self.subTest(declaration=declaration):
                result = self.run_source_worker(declaration)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(result.stdout.splitlines()[0])
                self.assertEqual(args[2:], ["--headless", *clock_args, "--script", "res://tests/fixture.gd"])

    def test_source_worker_rejects_invalid_clock_before_launch(self):
        result = self.run_source_worker("const FIXED_FPS := 0")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("FIXTURE_TEST PASS", result.stdout)

    def run_worker(self, code):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; export -f run_godot_checked; shift; bash -c \'run_godot_checked "$@"\' worker "$@"',
             "gate-test", str(ROOT / "tools/godot_gate.sh"), sys.executable, "-c", code],
            env={**os.environ, "POCKET_CIRCUIT_EXPECT_OUTPUT": "FIXTURE PASS"},
            capture_output=True, text=True, timeout=10,
        )

    def test_clean_success_marker_and_exit_pass(self):
        result = self.run_worker('print("FIXTURE PASS")')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nonzero_exit_after_success_marker_fails(self):
        for status in (1, 7, 124):
            with self.subTest(status=status):
                result = self.run_worker(f'import sys; print("FIXTURE PASS"); sys.exit({status})')
                self.assertNotEqual(result.returncode, 0, "tee must not hide the child process exit status")

    def test_script_error_with_zero_exit_fails(self):
        result = self.run_worker('print("FIXTURE PASS"); print("SCRIPT ERROR: broken fixture")')
        self.assertNotEqual(result.returncode, 0)

    def test_missing_completion_marker_fails(self):
        result = self.run_worker('print("still preparing")')
        self.assertNotEqual(result.returncode, 0)


class NativeAddonDocumentationTests(unittest.TestCase):
    def readme(self):
        return (ROOT / "vendor/gamestruments/README.md").read_text(encoding="utf-8")

    def test_current_vendored_release_passes_documentation_gate(self):
        errors = []
        validate_gamestruments_readme(self.readme(), errors)
        self.assertEqual(errors, [])

    def test_historical_version_mention_cannot_replace_release_heading(self):
        readme = self.readme().replace("# Gamestruments v1.1.0", "# Gamestruments v1.0.5-rc1", 1)
        self.assertIn("v1.1.0", readme)
        errors = []
        validate_gamestruments_readme(readme, errors)
        self.assertTrue(errors, "The current release must be the documented pin, not a historical mention")

    def test_credential_documentation_remains_required(self):
        for phrase in ("credential-free", "fine-grained GitHub PAT", "Contents: read"):
            with self.subTest(phrase=phrase):
                errors = []
                validate_gamestruments_readme(self.readme().replace(phrase, ""), errors)
                self.assertIn(f"vendor/gamestruments/README.md must document {phrase}", errors)


class NativeAddonSyncTests(unittest.TestCase):
    @contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tools").mkdir()
            shutil.copyfile(ROOT / "tools/sync_gamestruments.sh", root / "tools/sync_gamestruments.sh")
            source = root / "source"
            (source / "bin").mkdir(parents=True)
            (source / "gamestruments.gdextension").write_text("fixture descriptor\n")
            (source / "bin/libgamestruments_godot.so").write_bytes(b"N" * mmap.PAGESIZE)
            (source / "bin/gamestruments_godot.dll").write_bytes(b"windows fixture")
            destination = root / "addons/gamestruments/bin/libgamestruments_godot.so"
            destination.parent.mkdir(parents=True)
            destination.write_bytes(b"A" * (mmap.PAGESIZE * 3))
            yield root, source, destination

    def sync(self, root, source, extra_env=None):
        return subprocess.run(
            ["bash", str(root / "tools/sync_gamestruments.sh")],
            env={**os.environ, "GAMESTRUMENTS_ADDON_DIR": str(source), **(extra_env or {})},
            capture_output=True, text=True, timeout=10,
        )

    def test_changed_library_preserves_live_mapping(self):
        reader_code = '''
import ctypes, mmap, resource, sys
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
# This Linux shell-tool test must not write a core dump when testing the old bug.
PR_SET_DUMPABLE = 4
libc = ctypes.CDLL(None)
libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
assert libc.prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) == 0
with open(sys.argv[1], "rb") as library:
    with mmap.mmap(library.fileno(), 0, access=mmap.ACCESS_READ) as mapped:
        print("MAPPED_READY", flush=True)
        sys.stdin.readline()
        assert mapped[-1] == ord("A")
print("MAPPED_READER PASS", flush=True)
'''
        with self.fixture() as (root, source, destination):
            with subprocess.Popen(
                [sys.executable, "-c", reader_code, str(destination)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ) as reader:
                try:
                    ready, _, _ = select.select([reader.stdout], [], [], 10)
                    self.assertTrue(ready, "mapped reader did not become ready")
                    self.assertEqual(reader.stdout.readline(), "MAPPED_READY\n")
                    result = self.sync(root, source)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    stdout, stderr = reader.communicate("read\n", timeout=10)
                    self.assertEqual(reader.returncode, 0, f"live mapping died (SIGBUS is -7): {stderr}")
                    self.assertIn("MAPPED_READER PASS", stdout)
                    self.assertEqual(destination.read_bytes(), (source / "bin/libgamestruments_godot.so").read_bytes())
                finally:
                    if reader.poll() is None:
                        reader.kill()
                        reader.communicate()

    def test_unchanged_files_are_not_rewritten(self):
        with self.fixture() as (root, source, destination):
            result = self.sync(root, source)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted((root / "addons/gamestruments").rglob("*"))
            files = [path for path in files if path.is_file()]
            for path in files:
                os.utime(path, ns=(0, 0))
            before = {path: path.stat() for path in files}
            result = self.sync(root, source)
            self.assertEqual(result.returncode, 0, result.stderr)
            for path, previous in before.items():
                with self.subTest(file=path.name):
                    self.assertEqual(path.stat().st_ino, previous.st_ino)
                    self.assertEqual(path.stat().st_mtime_ns, previous.st_mtime_ns)

    def test_failed_copy_preserves_library_and_cleans_staging(self):
        with self.fixture() as (root, source, destination):
            original = destination.read_bytes()
            executables = root / "executables"
            executables.mkdir()
            copy = executables / "cp"
            copy.write_text(
                '#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\n'
                'if Path(sys.argv[-2]).name == "libgamestruments_godot.so":\n'
                '    Path(sys.argv[-1]).write_bytes(b"partial")\n    sys.exit(42)\n'
                'os.execv(os.environ["REAL_CP"], ["cp", *sys.argv[1:]])\n'
            )
            copy.chmod(0o755)
            result = self.sync(root, source, {
                "PATH": f"{executables}{os.pathsep}{os.environ['PATH']}", "REAL_CP": shutil.which("cp"),
            })
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(destination.read_bytes(), original)
            self.assertEqual(sorted(path.name for path in destination.parent.iterdir()), [destination.name])

    def test_flat_packaged_layout_is_supported(self):
        with self.fixture() as (root, source, destination):
            for path in (source / "bin").iterdir():
                path.rename(source / path.name)
            result = self.sync(root, source)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(destination.read_bytes(), (source / destination.name).read_bytes())
            self.assertEqual(
                (destination.parent / "gamestruments_godot.dll").read_bytes(),
                (source / "gamestruments_godot.dll").read_bytes(),
            )

    def test_missing_packaged_library_does_not_publish_any_file(self):
        with self.fixture() as (root, source, destination):
            original = destination.read_bytes()
            (source / "bin/gamestruments_godot.dll").unlink()
            result = self.sync(root, source)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(destination.read_bytes(), original)
            self.assertFalse((destination.parent.parent / "gamestruments.gdextension").exists())

    def test_comparison_error_does_not_overwrite_library(self):
        with self.fixture() as (root, source, destination):
            original = destination.read_bytes()
            executables = root / "executables"
            executables.mkdir()
            comparison = executables / "cmp"
            comparison.write_text("#!/usr/bin/env bash\nexit 2\n")
            comparison.chmod(0o755)
            result = self.sync(root, source, {"PATH": f"{executables}{os.pathsep}{os.environ['PATH']}"})
            self.assertEqual(result.returncode, 2)
            self.assertEqual(destination.read_bytes(), original)

    def test_missing_comparison_tool_fails_before_publishing(self):
        with self.fixture() as (root, source, destination):
            original = destination.read_bytes()
            executables = root / "executables"
            executables.mkdir()
            (executables / "bash").symlink_to(shutil.which("bash"))
            result = self.sync(root, source, {"PATH": str(executables)})
            self.assertEqual(result.returncode, 1)
            self.assertIn("cmp is required", result.stderr)
            self.assertEqual(destination.read_bytes(), original)
            self.assertFalse((destination.parent.parent / "gamestruments.gdextension").exists())

    def test_source_backend_preserves_open_library(self):
        with self.fixture() as (root, source, destination):
            original = destination.read_bytes()
            (source / "Cargo.toml").write_text("# source-copy fixture\n")
            (source / "crates/godot").mkdir(parents=True)
            (source / "target/release").mkdir(parents=True)
            (source / "gamestruments.gdextension").rename(source / "crates/godot/gamestruments.gdextension")
            compiled = source / "target/release/libgamestruments_godot.so"
            (source / "bin/libgamestruments_godot.so").rename(compiled)
            executables = root / "executables"
            executables.mkdir()
            cargo = executables / "cargo"
            cargo.write_text("#!/usr/bin/env bash\nexit 0\n")
            cargo.chmod(0o755)
            with destination.open("rb") as loaded:
                result = self.sync(root, source, {
                    "GAMESTRUMENTS_ADDON_DIR": "", "GAMESTRUMENTS_ROOT": str(source),
                    "PATH": f"{executables}{os.pathsep}{os.environ['PATH']}",
                })
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(loaded.read(), original)
            self.assertEqual(destination.read_bytes(), compiled.read_bytes())
