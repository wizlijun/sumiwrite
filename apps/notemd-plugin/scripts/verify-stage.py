#!/usr/bin/env python3
"""Verify the unsigned Sumi plugin stage and its checklist.json.

Library (tests import it) and CLI used by build-artifact.sh. Read-only apart
from --write-checklist; no signing, notarization or credentials involved.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

SCHEMA = 1
PLUGIN_ID = 'notemd.sumi'
HOST_CONTRACT = 1
FONT_SUFFIXES = {'.ttf', '.otf', '.woff', '.woff2', '.ttc', '.otc'}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_files(stage: Path) -> dict:
    """Map POSIX relative path -> sha256 for every regular file; reject symlinks and odd entries."""
    stage = Path(stage)
    assert stage.is_dir() and not stage.is_symlink(), 'Missing or unsafe stage directory'
    files = {}
    for path in sorted(stage.rglob('*')):
        rel = path.relative_to(stage).as_posix()
        assert not path.is_symlink(), 'Symlink in stage: ' + rel
        if path.is_dir():
            continue
        assert path.is_file(), 'Non-regular file in stage: ' + rel
        files[rel] = sha256(path)
    return files


def verify_fonts(stage: Path, source: Path) -> None:
    """Exact catalog/license bytes and no font payload anywhere in the plugin."""
    stage, source = Path(stage), Path(source)
    manifest = json.loads((source / 'manifest.json').read_bytes())
    expected = {'manifest.json'} | {a['file'] for a in manifest['assets'] if not a.get('postscript')}
    assert len(expected) == 10 and {p.name for p in (stage / 'ui/sumi').iterdir()} == expected, 'Unexpected ui/sumi contents'
    for name in expected:
        path = stage / 'ui/sumi' / name
        assert path.is_file() and not path.is_symlink() and path.read_bytes() == (source / name).read_bytes(), 'Catalog byte mismatch: ' + name
    for asset in manifest['assets']:
        if not asset.get('postscript'):
            raw = (stage / 'ui/sumi' / asset['file']).read_bytes()
            assert len(raw) == asset['size'] and hashlib.sha256(raw).hexdigest() == asset['sha256'], 'Asset digest mismatch: ' + asset['file']
    for path in stage.rglob('*'):
        assert path.suffix.lower() not in FONT_SUFFIXES, 'Large font payload in Sumi package'


def build_checklist(stage: Path, meta: dict) -> dict:
    checklist = dict(meta)
    checklist['files'] = stage_files(stage)
    return checklist


def verify_checklist(stage: Path, checklist: dict) -> None:
    assert checklist.get('schema') == SCHEMA, 'Unsupported checklist schema'
    declared = checklist.get('files')
    assert isinstance(declared, dict) and declared, 'Checklist has no files'
    actual = stage_files(stage)
    stage = Path(stage)
    assert (stage / 'manifest.json').is_file(), 'Stage has no manifest.json'
    binary = stage / 'bin' / 'notemd-sumi'
    assert binary.is_file() and os.access(binary, os.X_OK), 'bin/notemd-sumi is missing or not executable'
    assert not (stage / 'ui' / 'sounds').exists(), 'ui/sounds must not ship (sounds live in resources/sounds)'
    missing = sorted(set(declared) - set(actual))
    extra = sorted(set(actual) - set(declared))
    assert not missing, 'Files missing from stage: ' + ', '.join(missing)
    assert not extra, 'Files not in checklist: ' + ', '.join(extra)
    bad = sorted(k for k in declared if declared[k] != actual[k])
    assert not bad, 'Digest mismatch: ' + ', '.join(bad)


def core_tag(cargo_toml: Path) -> str:
    tags = set()
    for line in Path(cargo_toml).read_text().splitlines():
        m = re.match(r'\s*(write-core|sumi-protocol)\s*=.*\btag\s*=\s*"([^"]+)"', line)
        if m:
            tags.add(m.group(2))
    assert len(tags) == 1, 'write-core and sumi-protocol must share one tag, found: %s' % sorted(tags)
    return tags.pop()


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage', type=Path, required=True)
    p.add_argument('--verify-checklist', type=Path, metavar='CHECKLIST')
    p.add_argument('--verify-fonts', action='store_true')
    p.add_argument('--source', type=Path, help='resources/sumi (with --verify-fonts)')
    p.add_argument('--write-checklist', type=Path, metavar='OUT')
    p.add_argument('--manifest', type=Path)
    p.add_argument('--cargo-toml', type=Path)
    p.add_argument('--target')
    p.add_argument('--source-commit')
    p.add_argument('--source-tag', default='')
    a = p.parse_args(argv)
    try:
        if a.verify_fonts:
            assert a.source, '--verify-fonts needs --source'
            verify_fonts(a.stage, a.source)
        if a.write_checklist:
            assert a.manifest and a.cargo_toml and a.target and a.source_commit, 'missing checklist inputs'
            assert re.fullmatch(r'[0-9a-f]{40}', a.source_commit), 'source commit must be 40 hex digits'
            manifest = json.loads(a.manifest.read_bytes())
            version = manifest['version']
            assert manifest['id'] == PLUGIN_ID
            tag = a.source_tag or None
            if tag is not None:
                assert tag == 'notemd-plugin-v' + version, 'unexpected source tag'
            meta = {
                'schema': SCHEMA, 'plugin': PLUGIN_ID, 'version': version, 'target': a.target,
                'engines_notemd': manifest['engines']['notemd'], 'host_contract': HOST_CONTRACT,
                'core_tag': core_tag(a.cargo_toml), 'source_tag': tag, 'source_commit': a.source_commit,
            }
            a.write_checklist.write_text(json.dumps(build_checklist(a.stage, meta), indent=2) + '\n')
        if a.verify_checklist:
            verify_checklist(a.stage, json.loads(a.verify_checklist.read_bytes()))
            print('checklist OK')
    except AssertionError as e:
        print('verify-stage: ' + str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
