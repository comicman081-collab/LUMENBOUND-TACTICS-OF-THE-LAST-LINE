"""Stage and verify the external HD pages required by every Web export."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = (('full_density', 'r2'), ('full_density_effects', 'r1'), ('map_density', 'r1'), ('action_frames', 'r1'))
MANIFEST = 'density_sidecars.json'


def sha256(file: Path) -> str:
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_pages(root: Path) -> dict[str, Path]:
    pages = {}
    for family, revision in FAMILIES:
        source = root / 'godot/assets/runtime_web' / family / revision
        files = sorted(source.rglob('*.png'))
        if not files:
            raise ValueError(f'EMPTY_HD_SOURCE_FAMILY: {family}/{revision}')
        for file in files:
            if file.stat().st_size == 0:
                raise ValueError(f'EMPTY_HD_SOURCE_PAGE: {file}')
            pages[(Path('_hd') / family / revision / file.relative_to(source)).as_posix()] = file
    return pages


def validate(export: Path, root: Path = ROOT) -> dict:
    manifest = json.loads((export / MANIFEST).read_text(encoding='utf-8'))
    pages = manifest['pages']
    expected = source_pages(root)
    if manifest.get('schema_version') != 1 or set(pages) != set(expected):
        raise ValueError('HD_MANIFEST_SOURCE_SET_MISMATCH')
    actual = {file.relative_to(export).as_posix() for file in (export / '_hd').rglob('*') if file.is_file()}
    if actual != set(pages):
        raise ValueError('HD_EXPORT_PAGE_SET_MISMATCH')
    for name, source in expected.items():
        target = export / name
        if not target.resolve().is_relative_to(export.resolve()) or target.is_symlink():
            raise ValueError(f'UNSAFE_HD_EXPORT_PAGE: {name}')
        record = pages[name]
        if target.stat().st_size != record['bytes'] or sha256(target) != record['sha256']:
            raise ValueError(f'HD_EXPORT_HASH_MISMATCH: {name}')
        if source.stat().st_size != record['bytes'] or sha256(source) != record['sha256']:
            raise ValueError(f'HD_SOURCE_HASH_MISMATCH: {name}')
    return manifest


def stage(export: Path, root: Path = ROOT) -> dict:
    export = export.resolve()
    if not export.is_relative_to((root / 'builds').resolve()) or not (export / 'index.html').is_file():
        raise ValueError('NOT_A_PROJECT_LOCAL_WEB_EXPORT')
    if (export / '_hd').exists() or (export / MANIFEST).exists():
        raise ValueError('SIDECAR_DESTINATION_ALREADY_EXISTS')
    expected = source_pages(root)
    records = {}
    for name, source in expected.items():
        target = export / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        records[name] = {'bytes': source.stat().st_size, 'sha256': sha256(source)}
    manifest = {'schema_version': 1, 'pages': records}
    (export / MANIFEST).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return validate(export, root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    manifest = validate(args.export.resolve()) if args.validate_only else stage(args.export)
    print(f"LOCAL_DENSITY_SIDECARS_VERIFIED pages={len(manifest['pages'])}")


if __name__ == '__main__':
    main()
