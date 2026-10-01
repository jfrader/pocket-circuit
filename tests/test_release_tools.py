from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from test_success_marker import fixed_fps_for, marker_for


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
