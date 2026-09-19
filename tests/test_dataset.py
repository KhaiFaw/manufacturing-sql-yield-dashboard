"""Regression checks for the seeded source data; SQL remains the production cleaner."""
import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('generator', ROOT/'python/generate_data.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class DatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.previous_data = generator.DATA
        generator.DATA = Path(cls.temp.name)
        generator.main()
        cls.generated = {p.name: p.read_bytes() for p in generator.DATA.glob('*.csv')}
        with (generator.DATA/'raw_test_results.csv').open(newline='', encoding='utf-8') as f:
            cls.rows = list(csv.DictReader(f))

    @classmethod
    def tearDownClass(cls):
        generator.DATA = cls.previous_data
        cls.temp.cleanup()

    def test_checked_in_inputs_match_generator(self):
        for name, data in self.generated.items():
            self.assertEqual(data, (ROOT/'data'/name).read_bytes(), name)

    def test_repeat_generation_is_identical(self):
        generator.main()
        self.assertEqual(self.generated, {p.name:p.read_bytes() for p in generator.DATA.glob('*.csv')})

    def test_expected_count_and_unique_identifiers(self):
        self.assertEqual(len(self.rows), 8000)
        self.assertEqual(len({r['serial_number'] for r in self.rows}), 8000)

    def test_published_synthetic_outcome_counts(self):
        passes = sum(r['outcome_text'].strip().upper() in {'PASS','OK'} for r in self.rows)
        self.assertEqual(passes, 7558)
        self.assertEqual(len(self.rows)-passes, 442)

    def test_fixture_keeps_deliberate_messiness(self):
        outcomes = {r['outcome_text'] for r in self.rows}
        self.assertTrue({'OK','NG',' pass ',' fail '} <= outcomes)
        self.assertTrue(any(r['line_code'] != r['line_code'].strip() for r in self.rows))


if __name__ == '__main__':
    unittest.main()
