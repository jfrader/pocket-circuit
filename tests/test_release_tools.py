from pathlib import Path
from contextlib import contextmanager
import json
import mmap
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from test_success_marker import fixed_fps_for, marker_for
from validate_release_config import missing_uid_sidecars, stray_uid_sidecars, test_source_violations, validate_gamestruments_readme


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

    def test_failed_assertion_with_success_marker_and_zero_exit_fails(self):
        for failure in ("FAIL: deliberate", "  \tFAIL: deliberate", "Assertion failed", "at fixture: Assertion failed: deliberate"):
            for stream in ("sys.stdout", "sys.stderr"):
                with self.subTest(failure=failure, stream=stream):
                    result = self.run_worker(f'import sys; print({failure!r}, file={stream}); print("FIXTURE PASS")')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("failed assertion", result.stderr)
                    self.assertIn(failure, result.stdout)

    def test_failure_scan_does_not_reject_ordinary_output(self):
        result = self.run_worker('print("EXPECTED_FAIL: negative case checked"); print("FIXTURE PASS")')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_completion_marker_fails(self):
        result = self.run_worker('print("still preparing")')
        self.assertNotEqual(result.returncode, 0)

    def test_marker_must_be_a_whole_output_word(self):
        for line in ("FIXTURE PASS_NOT_FINISHED", "FIXTURE PASSED", "PRE_FIXTURE PASS", "NOT FIXTURE PASS", "FIXTURE PAS"):
            with self.subTest(line=line):
                result = self.run_worker(f'print({line!r}); print("shutting down")')
                self.assertNotEqual(result.returncode, 0, "a marker prefix or suffix must not count as completion")
                self.assertIn("expected success marker", result.stderr)

    def test_marker_with_details_and_later_shutdown_output_passes(self):
        for line in ("FIXTURE PASS", "FIXTURE PASS checked=12 assets=3"):
            with self.subTest(line=line):
                result = self.run_worker(f'print("loading"); print({line!r}); print("Godot shutdown: freed resources")')
                self.assertEqual(result.returncode, 0, result.stderr)


# Fake Godot for dispatcher tests: the first line of each fixture test selects
# its behaviour. Every launch is logged so tests can prove what actually ran.
# Processes it starts carry the fixture root in argv so tests can find them.
FAKE_DISPATCH_GODOT = r'''#!/usr/bin/env python3
import json, os, signal, subprocess, sys, time
root = sys.argv[sys.argv.index("--path") + 1]
script = sys.argv[sys.argv.index("--script") + 1].removeprefix("res://")
name = os.path.basename(script).removesuffix(".gd")
with open(os.path.join(root, "launches.log"), "a") as log:
    log.write(script + "\n")
with open(os.path.join(root, "events.log"), "a") as log:
    log.write(f"start {script}\n")
behaviour = open(os.path.join(root, script)).readline().removeprefix("#").strip()
marker = name.upper() + "_TEST PASS"

def record(directory, text):
    os.makedirs(os.path.join(root, directory), exist_ok=True)
    with open(os.path.join(root, directory, name), "a") as handle:
        handle.write(text)

def spawn_detached_sleeper():
    # Leaves its process group and session, as a daemonising helper would.
    sleeper = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", root],
                               start_new_session=True, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    record("pids", f"{sleeper.pid}\n")

def linger():
    # A slow test: still running when its worker is gone or the gate stops.
    record("pids", f"{os.getpid()}\n")
    record("ready", "ready\n")
    time.sleep(60)

def worker_argv_and_pid():
    # Walk up to the outermost bash worker that xargs launched for this test.
    found = None
    pid = os.getppid()
    while pid > 1:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            argv = handle.read().split(b"\0")
        if os.path.basename(argv[0]) == b"bash" and any(b"run_test_isolated" in arg for arg in argv):
            found = (pid, argv)
        with open(f"/proc/{pid}/stat") as handle:
            pid = int(handle.read().rsplit(")", 1)[1].split()[1])
    return found

if behaviour == "fail":
    print("FAIL: deliberate fixture failure")
    sys.exit(1)
if behaviour == "kill-worker":
    os.kill(worker_argv_and_pid()[0], signal.SIGKILL)
    spawn_detached_sleeper()
    linger()
if behaviour == "leak":
    spawn_detached_sleeper()
if behaviour == "linger":
    linger()
if behaviour == "report-env":
    names = ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "TMPDIR")
    record("env", json.dumps({key: os.environ.get(key) for key in names}))
    save = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                        "godot/app_userdata/fixture", name + ".json")
    os.makedirs(os.path.dirname(save), exist_ok=True)
    with open(save, "w") as handle:
        handle.write("{}")
if behaviour == "forge-duplicate":
    argv = worker_argv_and_pid()[1]
    results_file = argv[argv.index(script.encode()) - 1].decode()
    with open(results_file, "a") as results:
        results.write(f"PASS\t{script}\n")
print(marker)
with open(os.path.join(root, "events.log"), "a") as log:
    log.write(f"end {script}\n")
'''


def fixture_processes(root):
    """Live processes (not zombies) whose argv mentions the fixture root."""
    needle = os.fsencode(str(root))
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                argv = handle.read()
            with open(f"/proc/{entry}/stat") as handle:
                state = handle.read().rsplit(")", 1)[1].split()[0]
        except OSError:
            continue
        if needle in argv and state != "Z":
            found.append((int(entry), argv.replace(b"\0", b" ").decode(errors="replace")))
    return found


def process_parent(pid):
    with open(f"/proc/{pid}/stat") as handle:
        return int(handle.read().rsplit(")", 1)[1].split()[1])


def wait_for(predicate, seconds=15):
    deadline = time.monotonic() + seconds
    while not predicate():
        if time.monotonic() > deadline:
            return False
        time.sleep(0.02)
    return True


class GateDispatchTests(unittest.TestCase):
    @contextmanager
    def fixture(self, behaviours):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tests").mkdir()
            (root / "tools").mkdir()
            shutil.copyfile(ROOT / "tools/test_success_marker.py", root / "tools/test_success_marker.py")
            for name, behaviour in behaviours.items():
                marker = name.upper() + "_TEST PASS"
                (root / f"tests/{name}.gd").write_text(f'# {behaviour}\nprint("{marker}")\n')
            fake_godot = root / "godot"
            fake_godot.write_text(FAKE_DISPATCH_GODOT)
            fake_godot.chmod(0o755)
            # The gate's TMPDIR: everything it leaves here is leaked scratch.
            (root / "tmp").mkdir()
            try:
                yield root, fake_godot
            finally:
                # A broken gate can leave fixture processes behind; stop them so
                # one failure cannot leak into the host or later tests.
                def stopped():
                    for pid, _ in fixture_processes(root):
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    return not fixture_processes(root)
                wait_for(stopped)

    def launch(self, root, fake_godot, parallelism, tests, serial=(), env=None):
        # Output goes to files, not pipes: a leaked process holding a pipe open
        # would otherwise hide when the gate itself returned. Exercise the same
        # caller-owned cancellation stage as build_release.sh, under its flags.
        # Sentinel traps verify the stage restores handlers it temporarily owns;
        # after-gate stands for the exports that only success may reach.
        caller = '''source "$1"; shift
trap 'exit 99' HUP INT TERM
caller_traps="$(trap -p HUP INT TERM)"
gate_status=0
run_release_gate "$@" || gate_status=$?
[[ "$(trap -p HUP INT TERM)" == "$caller_traps" ]] || exit 98
(( gate_status == 0 )) || exit "$gate_status"
: > "$1/after-gate"
'''
        with open(root / "gate.out", "w") as out, open(root / "gate.err", "w") as err:
            return subprocess.Popen(
                ["bash", "-Eeuo", "pipefail", "-c", caller,
                 "gate-test", str(ROOT / "tools/godot_gate.sh"),
                 str(root), str(fake_godot), parallelism, *serial, "--", *(f"tests/{name}.gd" for name in tests)],
                env={**os.environ, "TMPDIR": str(root / "tmp"), **(env or {})},
                stdin=subprocess.DEVNULL, stdout=out, stderr=err, start_new_session=True,
            )

    def finish(self, root, gate):
        returncode = gate.wait(timeout=60)
        result = subprocess.CompletedProcess(gate.args, returncode, (root / "gate.out").read_text(), (root / "gate.err").read_text())
        log = root / "launches.log"
        launches = sorted(log.read_text().splitlines()) if log.exists() else []
        return result, launches

    def dispatch(self, root, fake_godot, parallelism, tests, serial=(), env=None):
        return self.finish(root, self.launch(root, fake_godot, parallelism, tests, serial, env))

    def assert_owned_state_released(self, root):
        # The caller is the first thing a group TERM kills, so the subreaper may
        # still be finishing its reap-and-exit for a moment after the gate
        # returns. Give that bounded grace, then require nothing to survive:
        # a surviving process could later recreate a result or scratch file.
        deadline = time.monotonic() + 3.0
        while fixture_processes(root) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(fixture_processes(root), [], "the gate returned while test processes were still running")
        self.assertEqual(sorted(os.listdir(root / "tmp")), [], "the gate left scratch files behind")

    def recorded_pids(self, root, name):
        path = root / "pids" / name
        return [int(line) for line in path.read_text().split()] if path.exists() else []

    def test_all_passing_tests_pass(self):
        names = {"alpha": "pass", "beta": "pass", "gamma": "pass", "delta": "pass"}
        with self.fixture(names) as (root, godot):
            result, launches = self.dispatch(root, godot, "2", names, serial=("tests/delta.gd",))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(launches, sorted(f"tests/{name}.gd" for name in names))
            for name in names:
                self.assertIn(f"[tests/{name}.gd] {name.upper()}_TEST PASS", result.stdout,
                              "Successful tests must retain their literal marker in gate evidence")
            self.assertTrue((root / "after-gate").exists())
            self.assert_owned_state_released(root)

    def test_direct_gate_call_keeps_its_scratch_cleanup(self):
        with self.fixture({"alpha": "pass"}) as (root, godot):
            result = subprocess.run(
                ["bash", "-Eeuo", "pipefail", "-c", 'source "$1"; shift; run_gate_tests "$@"',
                 "gate-test", str(ROOT / "tools/godot_gate.sh"), str(root), str(godot), "1", "--", "tests/alpha.gd"],
                env={**os.environ, "TMPDIR": str(root / "tmp")},
                capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_owned_state_released(root)

    def test_every_failed_test_is_reported_before_refusing(self):
        names = {"alpha": "fail", "beta": "pass", "gamma": "fail", "delta": "fail"}
        with self.fixture(names) as (root, godot):
            result, launches = self.dispatch(root, godot, "2", names, serial=("tests/delta.gd",))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(launches), 4, "one failure must not stop the remaining tests")
            for name in ("alpha", "gamma", "delta"):
                self.assertIn(f"  tests/{name}.gd\n", result.stderr)
            self.assertNotIn("  tests/beta.gd", result.stderr)
            self.assertNotIn("did not", result.stderr, "recorded test failures are not infrastructure failures")
            self.assert_owned_state_released(root)

    def test_every_test_gets_disposable_user_data(self):
        names = {"solo": "report-env", "alpha": "report-env", "beta": "report-env"}
        with self.fixture(names) as (root, godot):
            player = {key: root / "player" / key.lower() for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME")}
            for path in player.values():
                path.mkdir(parents=True)
                (path / "keep.txt").write_text("player data\n")
            result, _ = self.dispatch(root, godot, "2", names, serial=("tests/solo.gd",), env={k: str(v) for k, v in player.items()})
            self.assertEqual(result.returncode, 0, result.stderr)
            seen = {key: set() for key in player}
            for name in names:
                with self.subTest(test=name):
                    reported = json.loads((root / "env" / name).read_text())
                    for key, player_path in player.items():
                        value = reported[key]
                        self.assertTrue(value, f"{key} must be set for every test")
                        self.assertFalse(Path(value).is_relative_to(player_path), f"{key} must not be the player's")
                        self.assertTrue(Path(value).is_relative_to(root / "tmp"), f"{key} must be gate scratch")
                        self.assertFalse(Path(value).exists(), f"{key} must be removed once the gate returns")
                        seen[key].add(value)
                    self.assertTrue(Path(reported["TMPDIR"]).is_relative_to(root / "tmp"))
            for key, values in seen.items():
                self.assertEqual(len(values), len(names), f"{key} must differ between tests")
            for path in player.values():
                self.assertEqual(sorted(os.listdir(path)), ["keep.txt"], "tests must not touch player storage")
            # Serial still means alone: no other test started while solo ran.
            events = (root / "events.log").read_text().splitlines()
            start = events.index("start tests/solo.gd")
            self.assertEqual(events[start + 1], "end tests/solo.gd")
            self.assert_owned_state_released(root)

    def test_invalid_parallelism_fails_before_any_launch(self):
        with self.fixture({"alpha": "pass", "beta": "pass"}) as (root, godot):
            for parallelism in ("", "0", "-1", "abc", "2x", "1.5", " 2", "08"):
                with self.subTest(parallelism=parallelism):
                    result, launches = self.dispatch(root, godot, parallelism, ["alpha", "beta"])
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("parallelism", result.stderr)
                    self.assertEqual(launches, [])

    def test_xargs_launch_failure_fails_closed(self):
        with self.fixture({"alpha": "pass", "beta": "pass"}) as (root, godot):
            result, launches = self.dispatch(root, godot, "99999999999999999999", ["alpha", "beta"])
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(launches, [])
            self.assertIn("tests/alpha.gd (no result recorded", result.stderr)

    def test_worker_killed_before_recording_fails_closed(self):
        # The victim's fake Godot SIGKILLs its outer worker, so no trap in that
        # worker can run, then lingers with a detached child of its own.
        for serial in ((), ("tests/victim.gd",)):
            with self.subTest(serial=serial), self.fixture({"alpha": "pass", "victim": "kill-worker"}) as (root, godot):
                result, launches = self.dispatch(root, godot, "1", ["alpha", "victim"], serial=serial)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("tests/victim.gd", launches)
                self.assertEqual(len(self.recorded_pids(root, "victim")), 2, "the slow descendants must have started")
                self.assertIn("tests/victim.gd (no result recorded", result.stderr)
                self.assertNotIn("  tests/alpha.gd", result.stderr)
                self.assert_owned_state_released(root)

    def test_process_left_behind_by_a_passing_test_fails_and_is_stopped(self):
        for serial in ((), ("tests/leaky.gd",)):
            with self.subTest(serial=serial), self.fixture({"alpha": "pass", "leaky": "leak"}) as (root, godot):
                result, _ = self.dispatch(root, godot, "2", ["alpha", "leaky"], serial=serial)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.recorded_pids(root, "leaky")), 1)
                self.assertIn("left running", result.stderr)
                self.assert_owned_state_released(root)

    def test_terminated_gate_stops_its_tests_and_scratch(self):
        names = {"solo": "linger", "alpha": "linger", "beta": "linger"}
        # With parallelism 2 the first two scheduled tests start; serially, only solo.
        for serial, waiting in (((), ("solo", "alpha")), (("tests/solo.gd",), ("solo",))):
            with self.subTest(serial=serial), self.fixture(names) as (root, godot):
                gate = self.launch(root, godot, "2", names, serial=serial)
                started = wait_for(lambda: all((root / "ready" / name).exists() for name in waiting))
                os.killpg(gate.pid, signal.SIGTERM)
                result, _ = self.finish(root, gate)
                self.assertTrue(started, "lingering tests never started")
                self.assertEqual(result.returncode, 143, result.stderr)
                self.assertFalse((root / "after-gate").exists())
                self.assert_owned_state_released(root)

    def test_pid_terminated_caller_waits_for_tests_and_scratch(self):
        for serial in ((), ("tests/alpha.gd",)):
            with self.subTest(serial=serial), self.fixture({"alpha": "linger"}) as (root, godot):
                gate = self.launch(root, godot, "1", ["alpha"], serial=serial)
                try:
                    self.assertTrue(wait_for(lambda: (root / "ready/alpha").exists()))
                    os.kill(gate.pid, signal.SIGTERM)
                    try:
                        gate.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.fail("PID-only TERM did not stop the caller and its gate")
                    result, _ = self.finish(root, gate)
                    self.assertEqual(result.returncode, 143, result.stderr)
                    self.assertFalse((root / "after-gate").exists())
                    self.assert_owned_state_released(root)
                finally:
                    if gate.poll() is None:
                        os.killpg(gate.pid, signal.SIGTERM)
                        gate.wait(timeout=10)

    def test_killed_gate_still_stops_its_tests(self):
        # SIGKILL leaves the gate no chance to clean up, so its test processes
        # must be stopped by the owner it started; scratch removal needs the gate.
        with self.fixture({"alpha": "linger", "beta": "linger"}) as (root, godot):
            gate = self.launch(root, godot, "2", ["alpha", "beta"])
            try:
                self.assertTrue(wait_for(lambda: all((root / "ready" / name).exists() for name in ("alpha", "beta"))))
                owners = [pid for pid, argv in fixture_processes(root) if "gate_owner.py" in argv]
                self.assertEqual(len(owners), 1, "the parallel phase must run under one process owner")
                os.kill(process_parent(owners[0]), signal.SIGKILL)
                self.assertTrue(wait_for(lambda: not fixture_processes(root)), fixture_processes(root))
            finally:
                gate.kill()
                gate.wait(timeout=60)

    def test_duplicate_completion_record_fails_closed(self):
        with self.fixture({"alpha": "pass", "twice": "forge-duplicate"}) as (root, godot):
            result, _ = self.dispatch(root, godot, "2", ["alpha", "twice"])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("tests/twice.gd (duplicate results", result.stderr)

    def test_duplicate_scheduled_test_fails_before_any_launch(self):
        with self.fixture({"alpha": "pass"}) as (root, godot):
            result, launches = self.dispatch(root, godot, "2", ["alpha", "alpha"])
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(launches, [])


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


class UidSidecarTests(unittest.TestCase):
    def test_scripts_and_shaders_need_a_sidecar(self):
        paths = ["a.gd", "a.gd.uid", "b.gd", "c.gdshader", "d.tscn", "e.tres", "f.txt"]
        self.assertEqual(sorted(missing_uid_sidecars(paths)), ["b.gd", "c.gdshader"])

    def test_scene_and_resource_sidecars_are_stray(self):
        paths = ["a.gd", "a.gd.uid", "b.gdshader.uid", "c.tscn", "c.tscn.uid", "d.tres.uid"]
        self.assertEqual(sorted(stray_uid_sidecars(paths)), ["c.tscn.uid", "d.tres.uid"])


class TestSourceBanTests(unittest.TestCase):
    def test_assert_is_reported(self):
        self.assertEqual(
            test_source_violations({"tests/a_test.gd": "func _run():\n\tassert(x)\n"}),
            ["tests/a_test.gd: uses assert(); use a failing _expect"],
        )

    def test_unpathed_save_store_is_reported(self):
        violations = test_source_violations({"tests/b_test.gd": "var store = SAVE_STORE.new()\n"})
        self.assertEqual(violations, ["tests/b_test.gd: builds a SaveStore on the player's save path"])

    def test_pathed_store_and_expect_pass(self):
        source = 'var store = SAVE_STORE.new("user://tests/x.json")\nif not _expect(x, "x"): return\n'
        self.assertEqual(test_source_violations({"tests/c_test.gd": source}), [])
