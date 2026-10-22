"""Cross-check body exports against actual deployment and package contracts."""
import importlib.util
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
PRIMITIVE = ROOT.parent / 'primitive-mirrorme-bpx-quadruped-rbnx'


def load(path):
    return yaml.safe_load(path.read_text())


def exports(node):
    result = list(node.get('exports', []))
    for child in node.get('components', []):
        result.extend(exports(child))
    return result


class SomaProfilesTest(unittest.TestCase):
    def test_every_deployment_exports_only_its_provider_contracts(self):
        for path in ROOT.glob('robonix_manifest*.yaml'):
            with self.subTest(manifest=path.name):
                manifest = load(path)
                soma = load(ROOT / manifest['system']['soma'].get('robot_yaml', 'soma.yaml'))
                declared = {p['name']: p for p in manifest.get('primitive', [])}
                actual = exports(soma['robot'])
                self.assertEqual({e['provider_id'] for e in actual}, set(declared))
                for export in actual:
                    package = load(PRIMITIVE / declared[export['provider_id']]['manifest'])
                    self.assertEqual({c['path'] for c in export['capabilities']},
                                     {c['name'] for c in package['capabilities']})
                self.assertTrue((ROOT / soma['urdf']['path']).is_file())
                self.assertNotIn('dimensions', soma['robot'])

    def test_generated_profiles_are_current_and_share_body_geometry(self):
        spec = importlib.util.spec_from_file_location('generate_soma', ROOT / 'scripts/generate_soma_profiles.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        base = load(ROOT / 'soma.yaml')
        for profile in module.PROFILES:
            path = ROOT / ('soma.' + profile + '.yaml')
            self.assertEqual(path.read_text(), module.render(profile))
            doc = load(path)
            self.assertEqual(doc['urdf'], base['urdf'])
            self.assertEqual(doc['robot']['mass_kg'], base['robot']['mass_kg'])
        self.assertEqual(exports(load(ROOT / 'soma.no-motion.yaml')['robot']), [])


if __name__ == '__main__':
    unittest.main()
