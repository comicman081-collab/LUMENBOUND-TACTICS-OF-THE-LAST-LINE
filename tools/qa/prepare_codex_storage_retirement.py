"""Hash obsolete Sites workspaces and retain protected media before disposal.

This script never deletes. Native PowerShell performs the separately gated
disposal after the relocated preparation template passes its actual build check.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports/storage_cleanup_codex_20261002"
TEMPLATE = ROOT / "tools/web/sites_template"
MEDIA_KEEP = ROOT / "data_source/audio_source/sites_web_retained_20261002"
TARGETS = [ROOT / p for p in (
    "work/sites_20260920", "work/sites_r21_20261001",
    "work/sites_20260925_title_pop_v19.tar.gz",
    "reports/sites_r21_intro_fix_20261001/r21-intro-fix.tar.gz",
)]
MEDIA_EXT = {".mp3", ".wav", ".ogg", ".opus", ".flac", ".aac", ".m4a",
             ".mp4", ".ogv", ".webm", ".mov", ".avi", ".mkv"}
GIT = r"C:\Program Files\Git\cmd\git.exe"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def digest(stream) -> str:
    h = hashlib.sha256()
    while chunk := stream.read(4 * 1024 * 1024):
        h.update(chunk)
    return h.hexdigest()


def file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        return digest(stream)


def ordinary(path: Path) -> None:
    if not path.exists() or path.is_symlink() or path.is_junction():
        raise ValueError(f"Not an existing ordinary path: {path}")
    if path.resolve() != path.absolute() or ROOT not in path.resolve().parents:
        raise ValueError(f"Target outside exact project scope: {path}")


def walk(directory: Path):
    for base, dirs, names in os.walk(directory, followlinks=False):
        for name in dirs + names:
            path = Path(base) / name
            if path.is_symlink() or path.is_junction():
                raise ValueError(f"Refuse reparse-point descendant: {path}")
        for name in names:
            yield Path(base) / name


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    REPORT.mkdir(parents=True, exist_ok=True)
    records = []
    target_files = []
    target_summary = []
    free_before = shutil.disk_usage(ROOT).free
    for target in TARGETS:
        ordinary(target)
        files = list(walk(target)) if target.is_dir() else [target]
        total = 0
        for path in sorted(files):
            size = path.stat().st_size
            records.append({"path": rel(path), "bytes": size, "sha256": file_hash(path)})
            total += size
        target_files.extend(files)
        target_summary.append({"path": rel(target), "kind": "directory" if target.is_dir() else "file",
                               "bytes": total, "files": len(files)})
        print(f"Hashed {rel(target)}: {total:,} bytes, {len(files)} files", flush=True)
    with gzip.open(REPORT / "retired_files.jsonl.gz", "wt", encoding="utf-8") as out:
        for record in records:
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
    hashed = {record["path"]: record for record in records}

    # Find canonical copies outside the deletion targets. Do not traverse Git,
    # import caches, installed models, or unrelated project roots.
    canonical_by_size = {}
    excluded = {".git", ".godot", "node_modules", "__pycache__"}
    for base, dirs, names in os.walk(ROOT, followlinks=False):
        dirs[:] = [name for name in dirs if name not in excluded
                   and not (Path(base) / name).is_symlink()
                   and not (Path(base) / name).is_junction()
                   and Path(base) / name not in TARGETS]
        for name in names:
            path = Path(base) / name
            if path in TARGETS or path.suffix.lower() not in MEDIA_EXT or path.is_symlink():
                continue
            canonical_by_size.setdefault(path.stat().st_size, []).append(path)
    hash_cache = {}
    preserved = []

    def ensure_media(name: str, size: int, sha: str, copy_source) -> Path:
        for path in canonical_by_size.get(size, []):
            actual = hash_cache.setdefault(path, file_hash(path)) if path not in hash_cache else hash_cache[path]
            if actual == sha:
                preserved.append({"retired_source": name, "bytes": size, "sha256": sha,
                                  "retained_path": rel(path), "action": "existing_identical_copy"})
                return path
        # A production derivative is unique: preserve it byte for byte. Keep
        # voice relative names to allow later releases to reuse the same files.
        normalized = name.replace("\\", "/")
        if "/_audio/" in normalized:
            suffix = normalized.split("/_audio/", 1)[1]
        else:
            suffix = "other/" + sha[:16] + "_" + Path(normalized).name
        destination = MEDIA_KEEP / suffix
        if MEDIA_KEEP not in destination.resolve().parents:
            raise ValueError(f"Unsafe media member: {name}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if file_hash(destination) != sha:
                raise ValueError(f"Retained media collision: {destination}")
        else:
            copy_source(destination)
        if destination.stat().st_size != size or file_hash(destination) != sha:
            raise ValueError(f"Retained media verification failed: {destination}")
        hash_cache[destination] = sha
        canonical_by_size.setdefault(size, []).append(destination)
        preserved.append({"retired_source": name, "bytes": size, "sha256": sha,
                          "retained_path": rel(destination), "action": "copied_unique_media"})
        return destination

    def worker_routes(code: str):
        return json.loads(re.search(r"^const FILES = (.+);\r?$", code, re.M)[1])

    for path in target_files:
        if path.suffix.lower() in MEDIA_EXT and ".git" not in path.parts:
            item = hashed[rel(path)]
            ensure_media(rel(path), item["bytes"], item["sha256"], lambda dest, p=path: shutil.copy2(p, dest))

    # Older workspaces serve movies via opaque .bin parts. Protect the
    # reconstructed movie rather than losing it because of the chunk extension.
    for target in TARGETS[:2]:
        server = target / "dist/server/index.js"
        for name, entry in worker_routes(server.read_text(encoding="utf-8")).items():
            if Path(name).suffix.lower() not in MEDIA_EXT:
                continue
            parts = [target / "dist/client" / part.lstrip("/") for part in entry["parts"]]
            h = hashlib.sha256()
            size = 0
            for part in parts:
                ordinary(part)
                raw = part.read_bytes()
                h.update(raw)
                size += len(raw)
            sha = h.hexdigest()
            if sha != entry["hash"] or size != entry["size"]:
                raise ValueError(f"Streamed protected media is corrupt: {target} {name}")

            def join_parts(dest, paths=parts):
                with dest.open("wb") as out:
                    for part in paths:
                        with part.open("rb") as source:
                            shutil.copyfileobj(source, out)

            ensure_media(rel(target) + "/streamed" + name, size, sha, join_parts)

    for archive in TARGETS[2:]:
        with tarfile.open(archive, "r:gz") as tar:
            members = {m.name.removeprefix("./"): m for m in tar.getmembers() if m.isfile()}
            for name, member in members.items():
                if Path(name).suffix.lower() not in MEDIA_EXT:
                    continue
                with tar.extractfile(member) as stream:
                    sha = digest(stream)

                def copy_member(dest, m=member):
                    with tar.extractfile(m) as source, dest.open("wb") as out:
                        shutil.copyfileobj(source, out)

                ensure_media(rel(archive) + "::" + name, member.size, sha, copy_member)
            code = tar.extractfile(members["dist/server/index.js"]).read().decode("utf-8")
            for name, entry in worker_routes(code).items():
                if Path(name).suffix.lower() not in MEDIA_EXT:
                    continue
                parts = [members["dist/client/" + part.lstrip("/")] for part in entry["parts"]]
                h = hashlib.sha256()
                size = 0
                for member in parts:
                    with tar.extractfile(member) as stream:
                        while chunk := stream.read(4 * 1024 * 1024):
                            h.update(chunk)
                            size += len(chunk)
                sha = h.hexdigest()
                if sha != entry["hash"] or size != entry["size"]:
                    raise ValueError(f"Archive protected media is corrupt: {archive} {name}")

                def join_members(dest, entries=parts):
                    with dest.open("wb") as out:
                        for member in entries:
                            with tar.extractfile(member) as source:
                                shutil.copyfileobj(source, out)

                ensure_media(rel(archive) + "::streamed" + name, size, sha, join_members)
        print(f"Protected media checked in {rel(archive)}", flush=True)

    # Preserve the small preparation template, including the old checkout's
    # uncommitted verifier, before removing its large Git/dist workspace.
    template_files = [".openai/hosting.json", "dist/server/index.js", "package.json",
                      "package-lock.json", "scripts/verify-prebuilt.mjs"]
    provenance = []
    for name in template_files:
        source = TARGETS[0] / name
        destination = TEMPLATE / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        sha = file_hash(source)
        if file_hash(destination) != sha:
            raise ValueError(f"Template copy mismatch: {name}")
        provenance.append({"source": rel(source), "retained_path": rel(destination), "sha256": sha})
    write_json(TEMPLATE / "provenance.json", provenance)

    metadata = REPORT / "retained_sites_metadata"
    for target in TARGETS[:2]:
        destination = metadata / target.name
        destination.mkdir(parents=True, exist_ok=True)
        for folder in ("reports", "scripts", ".openai"):
            if (target / folder).is_dir():
                shutil.copytree(target / folder, destination / folder, dirs_exist_ok=True)
        # Preserve historical code/provenance compactly; never archive dist or
        # the giant object database merely to rename the storage problem.
        with zipfile.ZipFile(destination / "source_metadata.zip", "w", zipfile.ZIP_DEFLATED) as out:
            for path in walk(target):
                relative = path.relative_to(target)
                if relative.parts[0] in {"godot", "tools", "scripts", ".openai"} or len(relative.parts) == 1:
                    out.write(path, relative.as_posix())
        git_info = {}
        for key, args in (("head", ["rev-parse", "HEAD"]), ("status", ["status", "--short"]),
                          ("refs", ["show-ref"]), ("log", ["log", "--format=%H %s"])):
            process = subprocess.run([GIT, "-C", str(target), *args], capture_output=True, text=True, encoding="utf-8")
            if process.returncode:
                raise ValueError(f"Cannot preserve Git metadata: {target} {key}: {process.stderr}")
            git_info[key] = process.stdout
        patch = subprocess.run([GIT, "-C", str(target), "diff", "--binary", "HEAD"], capture_output=True, check=True)
        (destination / "uncommitted.patch").write_bytes(patch.stdout)
        write_json(destination / "git_provenance.json", git_info)

    write_json(REPORT / "protected_media.json", preserved)
    copied = {record["retained_path"]: record for record in preserved if record["action"] == "copied_unique_media"}
    write_json(MEDIA_KEEP / "preservation_manifest.json", list(copied.values()))
    write_json(REPORT / "retirement_plan.json", {
        "status": "INVENTORIED_AWAITING_TEMPLATE_VALIDATION",
        "project_root": str(ROOT), "free_bytes_before": free_before,
        "targets": target_summary, "retired_files_manifest": rel(REPORT / "retired_files.jsonl.gz"),
        "protected_media_manifest": rel(REPORT / "protected_media.json"),
        "gross_retirement_bytes": sum(item["bytes"] for item in target_summary),
        "unique_media_copies": len(copied), "unique_media_bytes_retained": sum(item["bytes"] for item in copied.values()),
        "kept": ["builds/web_visual_r21_release", "builds/web_visual_r22_release",
                 "godot/.godot", "work/new_chat_recovery_20260926", "all sound and intro source files"],
        "scope": "local obsolete Codex Sites workspaces and duplicate upload archives only; no live-site mutations",
    })
    print(json.dumps({"gross_bytes": sum(item["bytes"] for item in target_summary),
                      "unique_media_copies": len(copied), "unique_media_bytes": sum(item["bytes"] for item in copied.values()),
                      "protected_media_checks": len(preserved)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
