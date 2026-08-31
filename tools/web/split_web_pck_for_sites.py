#!/usr/bin/env python3
"""Split a Godot Web PCK into host-safe chunks and patch its loader.

The public game still exposes one virtual ``*.pck`` resource to Godot. The
patched Preloader fulfills that request by fetching the physical chunks in
order and joining their bodies with a ``ReadableStream``. This keeps peak
browser memory below an implementation that buffers every chunk first.

All generated artifacts are written before the source PCK is removed. Input
contracts are intentionally strict: an unfamiliar Godot shell is not patched
partially and is never left without its original PCK.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path


SCHEMA = "godot-pck-chunks-v1"
DEFAULT_CHUNK_SIZE = 20_000_000
MAX_CHUNK_SIZE = 20_000_000
COPY_BUFFER_SIZE = 1024 * 1024
HTML_MARKER = "GODOT_PCK_CHUNK_MANIFEST_V1"
JS_MARKER = "GODOT_PCK_CHUNK_STREAM_V1"


STREAM_HELPER = r'''
	/* GODOT_PCK_CHUNK_STREAM_V1 */
	function fetchChunkedGodotResource(file, expectedSize) {
		const manifest = globalThis.__GODOT_PCK_CHUNKS__;
		if (!manifest || file !== manifest.original.file) {
			return fetch(file);
		}
		if (manifest.schema !== 'godot-pck-chunks-v1'
				|| !Number.isSafeInteger(manifest.chunkSizeLimit)
				|| manifest.chunkSizeLimit <= 0 || manifest.chunkSizeLimit > 20000000
				|| !Number.isSafeInteger(manifest.original.size)
				|| manifest.original.size <= 0
				|| manifest.original.size !== expectedSize
				|| !Array.isArray(manifest.chunks)
				|| manifest.chunks.length === 0) {
			return Promise.reject(new Error(`Invalid chunk manifest for '${file}'`));
		}

		let declaredTotal = 0;
		for (let index = 0; index < manifest.chunks.length; index += 1) {
			const chunk = manifest.chunks[index];
			if (!chunk || chunk.index !== index
					|| typeof chunk.file !== 'string'
					|| chunk.file.length === 0
					|| chunk.file.includes('/') || chunk.file.includes('\\')
					|| !Number.isSafeInteger(chunk.size)
					|| chunk.size <= 0 || chunk.size > manifest.chunkSizeLimit) {
				return Promise.reject(new Error(`Invalid chunk ${index} for '${file}'`));
			}
			declaredTotal += chunk.size;
		}
		if (declaredTotal !== expectedSize) {
			return Promise.reject(new Error(`Chunk size mismatch for '${file}'`));
		}

		let chunkIndex = 0;
		let chunkReader = null;
		let chunkLoaded = 0;
		let totalLoaded = 0;
		const stream = new ReadableStream({
			pull: async function (controller) {
				try {
					while (true) {
						if (chunkReader === null) {
							if (chunkIndex >= manifest.chunks.length) {
								if (totalLoaded !== expectedSize) {
									throw new Error(`Assembled PCK size mismatch for '${file}'`);
								}
								controller.close();
								return;
							}
							const chunk = manifest.chunks[chunkIndex];
							const response = await fetch(chunk.file);
							if (!response.ok || !response.body) {
								throw new Error(`Failed loading PCK chunk '${chunk.file}'`);
							}
							chunkReader = response.body.getReader();
							chunkLoaded = 0;
						}

						const result = await chunkReader.read();
						if (result.done) {
							const chunk = manifest.chunks[chunkIndex];
							if (chunkLoaded !== chunk.size) {
								throw new Error(`Size mismatch for PCK chunk '${chunk.file}'`);
							}
							chunkReader = null;
							chunkIndex += 1;
							continue;
						}
						if (result.value) {
							const chunk = manifest.chunks[chunkIndex];
							chunkLoaded += result.value.byteLength;
							totalLoaded += result.value.byteLength;
							if (chunkLoaded > chunk.size || totalLoaded > expectedSize) {
								throw new Error(`Oversized PCK chunk '${chunk.file}'`);
							}
							controller.enqueue(result.value);
							return;
						}
					}
				} catch (error) {
					controller.error(error);
				}
			},
			cancel: function (reason) {
				return chunkReader ? chunkReader.cancel(reason) : undefined;
			},
		});
		return Promise.resolve(new Response(stream, {
			status: 200,
			headers: {
				'content-length': String(expectedSize),
				'content-type': 'application/octet-stream',
			},
		}));
	}
'''.strip("\n")


def _one_file(root: Path, pattern: str, label: str) -> Path:
    matches = sorted(root.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one {label} in {root}, found {len(matches)}")
    if not matches[0].is_file() or matches[0].stat().st_size <= 0:
        raise SystemExit(f"missing or empty {label}: {matches[0]}")
    return matches[0]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(COPY_BUFFER_SIZE):
            digest.update(block)
    return digest.hexdigest()


def _validate_filename(filename: str) -> None:
    if Path(filename).name != filename or "/" in filename or "\\" in filename:
        raise SystemExit(f"unsafe generated filename: {filename!r}")


def _patch_loader(loader: str) -> str:
    if JS_MARKER in loader:
        raise SystemExit("index.js is already patched for chunked PCK loading")
    signature = "\tfunction loadFetch(file, tracker, fileSize, raw) {"
    if loader.count(signature) != 1:
        raise SystemExit("expected exactly one Godot Preloader loadFetch function")
    fetch_needle = "\t\treturn fetch(file).then(async function (response) {"
    if loader.count(fetch_needle) != 1:
        raise SystemExit("expected exactly one loadFetch fetch call in index.js")
    loader = loader.replace(signature, STREAM_HELPER + "\n\n" + signature, 1)
    return loader.replace(
        fetch_needle,
        "\t\treturn fetchChunkedGodotResource(file, fileSize).then(async function (response) {",
        1,
    )


def _patch_html(html: str, manifest: dict, pck_name: str, pck_size: int) -> str:
    if HTML_MARKER in html or "__GODOT_PCK_CHUNKS__" in html:
        raise SystemExit("index.html already contains a PCK chunk manifest")
    size_pattern = re.compile(rf'("{re.escape(pck_name)}"\s*:\s*)(\d+)')
    matches = list(size_pattern.finditer(html))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one fileSizes entry for {pck_name}")
    configured_size = int(matches[0].group(2))
    if configured_size != pck_size:
        raise SystemExit(
            f"index.html PCK fileSizes mismatch: configured={configured_size}, actual={pck_size}"
        )
    script_needle = '\t\t<script src="index.js"></script>'
    if html.count(script_needle) != 1:
        raise SystemExit("expected exactly one Godot index.js script tag")
    embedded = {
        "schema": manifest["schema"],
        "chunkSizeLimit": manifest["chunk_size_limit"],
        "original": manifest["original"],
        "chunks": manifest["chunks"],
    }
    payload = json.dumps(embedded, ensure_ascii=True, separators=(",", ":"))
    injection = (
        f'\t\t<script id="godot-pck-chunk-manifest">/* {HTML_MARKER} */\n'
        f"\t\tglobalThis.__GODOT_PCK_CHUNKS__ = Object.freeze({payload});\n"
        "\t\t</script>\n"
    )
    patched = html.replace(script_needle, injection + script_needle, 1)
    after = list(size_pattern.finditer(patched))
    if len(after) != 1 or int(after[0].group(2)) != configured_size:
        raise SystemExit("PCK fileSizes changed while injecting chunk manifest")
    return patched


def _patch_service_worker(worker: str, pck_name: str, chunk_names: list[str]) -> str:
    declaration = re.compile(r"const CACHEABLE_FILES = (\[[^;\r\n]*\]);")
    matches = list(declaration.finditer(worker))
    if len(matches) != 1:
        raise SystemExit("expected exactly one service-worker CACHEABLE_FILES declaration")
    try:
        cacheable = json.loads(matches[0].group(1))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid CACHEABLE_FILES JSON: {exc}") from exc
    if not isinstance(cacheable, list) or cacheable.count(pck_name) != 1:
        raise SystemExit(f"CACHEABLE_FILES must contain {pck_name} exactly once")
    replacement: list[str] = []
    for item in cacheable:
        if item == pck_name:
            replacement.extend(chunk_names)
        else:
            replacement.append(item)
    encoded = json.dumps(replacement, ensure_ascii=True, separators=(",", ":"))
    patched = worker[:matches[0].start(1)] + encoded + worker[matches[0].end(1):]
    if pck_name in json.loads(declaration.search(patched).group(1)):
        raise SystemExit("original PCK remained in CACHEABLE_FILES")
    return patched


def split_export(root: Path, chunk_size: int) -> dict:
    root = root.resolve()
    if not root.is_dir():
        raise SystemExit(f"export directory does not exist: {root}")
    if chunk_size <= 0 or chunk_size > MAX_CHUNK_SIZE:
        raise SystemExit(f"chunk size must be between 1 and {MAX_CHUNK_SIZE} bytes")

    pck = _one_file(root, "*.pck", "PCK file")
    html_path = _one_file(root, "index.html", "index.html")
    loader_path = _one_file(root, "index.js", "index.js")
    worker_path = _one_file(root, "index.service.worker.js", "service worker")
    pck_size = pck.stat().st_size
    chunk_count = (pck_size + chunk_size - 1) // chunk_size
    chunk_names = [f"{pck.name}.chunk-{index:03d}" for index in range(chunk_count)]
    for name in chunk_names:
        _validate_filename(name)
        if (root / name).exists():
            raise SystemExit(f"refusing to overwrite existing PCK chunk: {name}")
    manifest_name = f"{pck.name}.chunks.json"
    _validate_filename(manifest_name)
    manifest_path = root / manifest_name
    if manifest_path.exists():
        raise SystemExit(f"refusing to overwrite existing chunk manifest: {manifest_name}")

    loader_source = loader_path.read_text(encoding="utf-8")
    html_source = html_path.read_text(encoding="utf-8")
    worker_source = worker_path.read_text(encoding="utf-8")
    patched_loader = _patch_loader(loader_source)

    chunks: list[dict] = []
    original_digest = hashlib.sha256()
    with tempfile.TemporaryDirectory(prefix=".pck-split-", dir=root) as temp_name:
        temp_root = Path(temp_name)
        with pck.open("rb") as source:
            for index, chunk_name in enumerate(chunk_names):
                temp_path = temp_root / chunk_name
                digest = hashlib.sha256()
                written = 0
                with temp_path.open("wb") as target:
                    while written < chunk_size:
                        block = source.read(min(COPY_BUFFER_SIZE, chunk_size - written))
                        if not block:
                            break
                        target.write(block)
                        digest.update(block)
                        original_digest.update(block)
                        written += len(block)
                if written <= 0 or written > chunk_size:
                    raise SystemExit(f"invalid generated chunk size for {chunk_name}: {written}")
                chunks.append({
                    "index": index,
                    "file": chunk_name,
                    "size": written,
                    "sha256": digest.hexdigest(),
                })
            if source.read(1):
                raise SystemExit("PCK contained unconsumed data after splitting")

        if sum(item["size"] for item in chunks) != pck_size:
            raise SystemExit("generated chunk sizes do not equal the original PCK size")
        manifest = {
            "schema": SCHEMA,
            "chunk_size_limit": chunk_size,
            "original": {
                "file": pck.name,
                "size": pck_size,
                "sha256": original_digest.hexdigest(),
            },
            "chunks": chunks,
        }
        patched_html = _patch_html(html_source, manifest, pck.name, pck_size)
        patched_worker = _patch_service_worker(worker_source, pck.name, chunk_names)

        # Patch contracts and every generated byte are now validated. Publish
        # all replacements while the recoverable source PCK still exists.
        for chunk in chunks:
            (temp_root / chunk["file"]).replace(root / chunk["file"])
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8", newline="\n",
        )
        loader_path.write_text(patched_loader, encoding="utf-8", newline="\n")
        html_path.write_text(patched_html, encoding="utf-8", newline="\n")
        worker_path.write_text(patched_worker, encoding="utf-8", newline="\n")

    # Removing the original is deliberately last. A failed validation or write
    # therefore leaves the ordinary, unsplit Godot export runnable.
    pck.unlink()
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_dir", type=Path, help="fresh Godot Web export directory")
    parser.add_argument(
        "--chunk-size-bytes", type=int, default=DEFAULT_CHUNK_SIZE,
        help=f"maximum physical chunk size (default: {DEFAULT_CHUNK_SIZE})",
    )
    args = parser.parse_args()
    manifest = split_export(args.export_dir, args.chunk_size_bytes)
    print(
        "SITES_PCK_SPLIT_OK "
        f"original={manifest['original']['file']} size={manifest['original']['size']} "
        f"chunks={len(manifest['chunks'])} max={max(c['size'] for c in manifest['chunks'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
