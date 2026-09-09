from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from test_success_marker import marker_for


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
