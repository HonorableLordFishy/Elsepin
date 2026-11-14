import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_validation_simulator import choose_destination


class ValidationSimulatorTests(unittest.TestCase):
    def runtime(self, version, model, available=True):
        return dict(identifier='com.apple.CoreSimulator.SimRuntime.iOS-' + version,
                    version=version, isAvailable=available,
                    supportedDeviceTypes=[dict(name=model, identifier=model, productFamily='iPhone')])

    def test_prefers_sdk_match_over_newer_device_specific_runtime(self):
        stable = self.runtime('27.1', 'iPhone 17')
        special = self.runtime('27.2', 'iPhone 19')
        runtime, model = choose_destination({'runtimes': [special, stable]}, '27.1')
        self.assertEqual(runtime, stable)
        self.assertEqual(model['name'], 'iPhone 17')

    def test_fallback_selects_only_a_supported_model(self):
        special = self.runtime('27.2', 'iPhone 19')
        runtime, model = choose_destination({'runtimes': [special]}, '27.1')
        self.assertIn(model, runtime['supportedDeviceTypes'])
        self.assertEqual(model['name'], 'iPhone 19')

    def test_unavailable_runtime_is_not_selected(self):
        with self.assertRaisesRegex(RuntimeError, 'No available iOS runtime'):
            choose_destination({'runtimes': [self.runtime('27.1', 'iPhone 17', False)]}, '27.1')
