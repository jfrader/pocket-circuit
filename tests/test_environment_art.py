import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
HAS_PILLOW = importlib.util.find_spec("PIL") is not None
if HAS_PILLOW:
    from PIL import Image
    import prepare_track_art


@unittest.skipUnless(HAS_PILLOW, "Asset preparation tests require Pillow")
class EnvironmentArtTests(unittest.TestCase):
    def test_material_retains_painted_color_range_and_wraps_without_seams(self):
        source = Image.new("RGB", (80, 64))
        source.putdata([(x * 3, y * 4, x + y) for y in range(64) for x in range(80)])

        material = prepare_track_art.repeating_material(source)

        self.assertEqual(material.size, (512, 512))
        self.assertEqual(material.mode, "RGB")
        self.assertGreater(len(material.getcolors(material.width * material.height)), 1000)
        for coordinate in range(512):
            with self.subTest(coordinate=coordinate):
                self.assertEqual(material.getpixel((0, coordinate)), material.getpixel((511, coordinate)))
                self.assertEqual(material.getpixel((coordinate, 0)), material.getpixel((coordinate, 511)))
                self.assertEqual(material.getpixel((255, coordinate)), material.getpixel((256, coordinate)))
                self.assertEqual(material.getpixel((coordinate, 255)), material.getpixel((coordinate, 256)))

    def test_save_png_preserves_alpha_and_does_not_rewrite_identical_output(self):
        image = Image.new("RGBA", (8, 8), (40, 70, 90, 120))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "nested" / "sprite.png"
            prepare_track_art.save_png(image, path)
            with Image.open(path) as saved:
                self.assertEqual(saved.mode, image.mode)
                self.assertEqual(saved.tobytes(), image.tobytes())
            os.utime(path, ns=(1_000_000_000, 1_000_000_000))
            before = path.stat().st_mtime_ns

            prepare_track_art.save_png(image, path)

            self.assertEqual(path.stat().st_mtime_ns, before)

    def test_compatibility_entry_point_forwards_the_authoritative_contract(self):
        library = types.ModuleType("prepare_environment_library")
        library.prepare = Mock()
        definitions = [{"id": "approved-asset", "style": "overhead_gouache_v1"}]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "data").mkdir()
            (root / "data/world_prop_art.json").write_text(json.dumps(definitions))
            with patch.object(prepare_track_art, "ROOT", root), patch.dict(sys.modules, {library.__name__: library}):
                prepare_track_art.main()

        library.prepare.assert_called_once_with(definitions)
