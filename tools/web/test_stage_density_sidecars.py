"""Regression coverage for incomplete or corrupted Web HD deliveries."""
import tempfile
import unittest
from pathlib import Path

from stage_density_sidecars import FAMILIES, stage, validate


class SidecarDeliveryTests(unittest.TestCase):
    def setUp(self):
        project = Path(__file__).resolve().parents[2]
        scratch = project / 'reports/local_audit_20260910/test_scratch'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.export = self.root / 'builds/test_web'
        self.export.mkdir(parents=True)
        (self.export / 'index.html').write_text('<!doctype html>', encoding='utf-8')
        for family, revision in FAMILIES:
            folder = self.root / 'godot/assets/runtime_web' / family / revision / 'CHR001'
            folder.mkdir(parents=True)
            (folder / 'page_00.png').write_bytes(b'fixture-' + family.encode())

    def test_all_families_are_delivered_and_verified(self):
        result = stage(self.export, self.root)
        self.assertEqual(len(result['pages']), len(FAMILIES))
        self.assertEqual(validate(self.export, self.root), result)

    def test_missing_page_is_rejected(self):
        result = stage(self.export, self.root)
        (self.export / next(iter(result['pages']))).unlink()
        with self.assertRaisesRegex(ValueError, 'PAGE_SET_MISMATCH'):
            validate(self.export, self.root)

    def test_corrupted_page_is_rejected(self):
        result = stage(self.export, self.root)
        file = self.export / next(iter(result['pages']))
        file.write_bytes(b'x' * file.stat().st_size)
        with self.assertRaisesRegex(ValueError, 'HASH_MISMATCH'):
            validate(self.export, self.root)

    def test_missing_source_family_is_rejected_before_copy(self):
        family, revision = FAMILIES[-1]
        (self.root / 'godot/assets/runtime_web' / family / revision / 'CHR001/page_00.png').unlink()
        with self.assertRaisesRegex(ValueError, 'EMPTY_HD_SOURCE_FAMILY'):
            stage(self.export, self.root)
        self.assertFalse((self.export / '_hd').exists())

    def test_existing_delivery_cannot_be_overwritten(self):
        stage(self.export, self.root)
        with self.assertRaisesRegex(ValueError, 'DESTINATION_ALREADY_EXISTS'):
            stage(self.export, self.root)

    def test_stale_source_and_unexpected_payload_are_rejected(self):
        stage(self.export, self.root)
        extra = self.export / '_hd/unwanted.txt'
        extra.write_text('unexpected', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'PAGE_SET_MISMATCH'):
            validate(self.export, self.root)
        extra.unlink()
        family, revision = FAMILIES[0]
        (self.root / 'godot/assets/runtime_web' / family / revision / 'CHR001/page_00.png').write_bytes(b'new source')
        with self.assertRaisesRegex(ValueError, 'SOURCE_HASH_MISMATCH'):
            validate(self.export, self.root)


if __name__ == '__main__':
    unittest.main()
