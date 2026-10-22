"""Resolve URDF-relative meshes for RViz's robot_description topic consumer.

Write a local visualization copy; do not alter the portable deployment URDF.
"""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


def prepare(source, output):
    source = source.resolve(strict=True)
    tree = ET.parse(source)
    for mesh in tree.iter('mesh'):
        name = mesh.attrib['filename']
        if '://' in name:
            continue
        target = (source.parent / name).resolve(strict=True)
        mesh.set('filename', target.as_uri())
    with output.open('xb') as stream:
        tree.write(stream, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prepare(args.source, args.output)
