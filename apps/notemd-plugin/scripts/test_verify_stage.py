import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'resources' / 'sumi'

spec = importlib.util.spec_from_file_location('verify_stage', HERE / 'verify-stage.py')
vs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vs)

META = {
    'schema': 1, 'plugin': 'notemd.sumi', 'version': '0.1.16',
    'target': 'aarch64-apple-darwin', 'engines_notemd': '>=6.1111.1',
    'host_contract': 1, 'core_tag': 'core-v0.1.0',
    'source_tag': None, 'source_commit': 'a' * 40,
}


def make_stage(root: Path) -> Path:
    stage = root / 'stage'
    (stage / 'bin').mkdir(parents=True)
    (stage / 'ui').mkdir()
    (stage / 'bin' / 'notemd-sumi').write_bytes(b'binary')
    (stage / 'manifest.json').write_text('{}')
    (stage / 'ui' / 'index.html').write_text('<html></html>')
    shutil.copytree(SOURCE, stage / 'ui' / 'sumi')
    return stage


class VerifyStageTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.stage = make_stage(self.root)

    def test_checklist_roundtrip(self):
        checklist = vs.build_checklist(self.stage, META)
        self.assertIn('bin/notemd-sumi', checklist['files'])
        self.assertIn('ui/sumi/manifest.json', checklist['files'])
        vs.verify_checklist(self.stage, checklist)

    def test_extra_file_rejected(self):
        checklist = vs.build_checklist(self.stage, META)
        (self.stage / 'extra.txt').write_text('x')
        with self.assertRaises(AssertionError):
            vs.verify_checklist(self.stage, checklist)

    def test_missing_file_rejected(self):
        checklist = vs.build_checklist(self.stage, META)
        (self.stage / 'ui' / 'index.html').unlink()
        with self.assertRaises(AssertionError):
            vs.verify_checklist(self.stage, checklist)

    def test_digest_mismatch_rejected(self):
        checklist = vs.build_checklist(self.stage, META)
        (self.stage / 'bin' / 'notemd-sumi').write_bytes(b'tampered')
        with self.assertRaises(AssertionError):
            vs.verify_checklist(self.stage, checklist)

    def test_symlink_rejected(self):
        (self.stage / 'link').symlink_to(self.stage / 'manifest.json')
        with self.assertRaises(AssertionError):
            vs.build_checklist(self.stage, META)

    def test_fonts_accepts_real_catalog(self):
        vs.verify_fonts(self.stage, SOURCE)

    def test_font_payload_rejected(self):
        (self.stage / 'ui' / 'assets').mkdir()
        (self.stage / 'ui' / 'assets' / 'x.woff2').write_bytes(b'font')
        with self.assertRaises(AssertionError):
            vs.verify_fonts(self.stage, SOURCE)

    def test_catalog_bytes_must_match_source(self):
        path = self.stage / 'ui' / 'sumi' / 'manifest.json'
        path.write_bytes(path.read_bytes() + b' ')
        with self.assertRaises(AssertionError):
            vs.verify_fonts(self.stage, SOURCE)

    def test_license_bytes_must_match_source(self):
        path = self.stage / 'ui' / 'sumi' / 'IBMPlexMono-OFL.txt'
        path.write_bytes(path.read_bytes() + b'\n')
        with self.assertRaises(AssertionError):
            vs.verify_fonts(self.stage, SOURCE)

    def test_catalog_extra_file_rejected(self):
        (self.stage / 'ui' / 'sumi' / 'extra.txt').write_text('x')
        with self.assertRaises(AssertionError):
            vs.verify_fonts(self.stage, SOURCE)


if __name__ == '__main__':
    unittest.main()
