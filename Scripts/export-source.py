#!/usr/bin/env python3
"""Prepare a reviewed source-only snapshot, without local Git history or logs."""
from pathlib import Path
import hashlib
import json
import shutil
import tempfile
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = root / "Config/public-source-files.txt"
    names = [line.strip() for line in manifest.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if len(names) != len(set(names)):
        raise SystemExit("Duplicate paths in publication manifest.")
    if not {"LICENSE", "README.md", "Package.swift"}.issubset(names):
        raise SystemExit("The reviewed manifest must include LICENSE, README.md and Package.swift.")
    files = []
    for name in names:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit(f"Unsafe manifest path: {name}")
        source = root / relative
        if any(part.is_symlink() for part in [source, *source.parents]):
            raise SystemExit(f"Symlinks are not allowed in the source snapshot: {name}")
        if not source.is_file():
            raise SystemExit(f"Required publication file is missing: {name}")
        if {".git", ".build", "dist", "outputs", "work", ".superpowers", ".env"}.intersection(relative.parts):
            raise SystemExit(f"Local-only path in publication manifest: {name}")
        files.append((name, source))

    publication = root / "publication"
    publication.mkdir(exist_ok=True)
    destination = publication / "Tepal"
    archive = publication / "Tepal-source.zip"
    checksums = publication / "Tepal-source-files.sha256.json"
    if any(p.exists() for p in [destination, archive, checksums]):
        raise SystemExit("A publication candidate already exists. Move it aside before exporting again.")

    with tempfile.TemporaryDirectory(prefix=".source-stage-", dir=publication) as scratch:
        scratch = Path(scratch)
        staged = scratch / "Tepal"
        hashes = {}
        for name, source in files:
            target = staged / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            target.chmod(0o755 if name.startswith("Scripts/") else 0o644)
            hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
        zip_path = scratch / archive.name
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as output:
            for name, _ in files:
                info = zipfile.ZipInfo("Tepal/" + name, date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = ((0o100755 if name.startswith("Scripts/") else 0o100644) << 16)
                info.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(info, (staged / name).read_bytes())
        with zipfile.ZipFile(zip_path) as check:
            if check.testzip() is not None:
                raise SystemExit("Source archive verification failed.")
        shutil.move(str(staged), str(destination))
        shutil.move(str(zip_path), str(archive))
        checksums.write_text(json.dumps(hashes, indent=2, sort_keys=True) + "\n")
    print(f"Prepared {len(files)} reviewed files: {archive}")
    print("This is a local source candidate. Nothing was uploaded and no Git history was rewritten.")


if __name__ == "__main__":
    main()
