import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rviz_model', ROOT / 'scripts/prepare_rviz_model.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RvizModelTest(unittest.TestCase):
    def test_visualization_copy_resolves_all_meshes_without_changing_source(self):
        source = ROOT / 'urdf/mirrorme_bpx.urdf'
        original = source.read_bytes()
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'rviz.urdf'
            module.prepare(source, output)
            tree = ET.parse(output)
            self.assertEqual(len(tree.findall('link')), 18)
            for mesh in tree.iter('mesh'):
                self.assertTrue(mesh.attrib['filename'].startswith('file:///'))
            self.assertEqual(source.read_bytes(), original)
            with self.assertRaises(FileExistsError):
                module.prepare(source, output)

    def test_missing_mesh_is_reported_before_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            source, output = Path(temp) / 'in.urdf', Path(temp) / 'out.urdf'
            source.write_text('<robot><mesh filename="missing.obj"/></robot>')
            with self.assertRaises(FileNotFoundError):
                module.prepare(source, output)
            self.assertFalse(output.exists())
