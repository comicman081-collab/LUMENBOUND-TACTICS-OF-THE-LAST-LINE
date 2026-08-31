#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import split_web_pck_for_sites as splitter


LOADER_FIXTURE = """const Preloader = function () {
\tfunction getTrackedResponse(response, load_status) { return response; }

\tfunction loadFetch(file, tracker, fileSize, raw) {
\t\ttracker[file] = { total: fileSize || 0, loaded: 0, done: false };
\t\treturn fetch(file).then(async function (response) {
\t\t\tif (!response.ok) { throw new Error('load failed'); }
\t\t\treturn raw ? response : response.arrayBuffer();
\t\t});
\t}
};
"""


def make_fixture(root: Path, loader: str = LOADER_FIXTURE) -> bytes:
    payload = bytes((index * 37 + 11) % 256 for index in range(173))
    (root / "game.pck").write_bytes(payload)
    (root / "index.js").write_text(loader, encoding="utf-8")
    (root / "index.html").write_text(
        '<!doctype html>\n<html><body>\n'
        '\t\t<script src="index.js"></script>\n'
        '<script>const GODOT_CONFIG = {"fileSizes":{"game.pck":173}};</script>\n'
        '</body></html>\n',
        encoding="utf-8",
    )
    (root / "index.service.worker.js").write_text(
        'const CACHEABLE_FILES = ["game.wasm","game.pck"];\n',
        encoding="utf-8",
    )
    return payload


class SplitWebPckForSitesTest(unittest.TestCase):
    def test_split_patch_and_stream_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            payload = make_fixture(root)
            manifest = splitter.split_export(root, chunk_size=41)

            self.assertFalse((root / "game.pck").exists())
            self.assertEqual([41, 41, 41, 41, 9], [c["size"] for c in manifest["chunks"]])
            self.assertEqual(hashlib.sha256(payload).hexdigest(), manifest["original"]["sha256"])
            rebuilt = b"".join((root / item["file"]).read_bytes() for item in manifest["chunks"])
            self.assertEqual(payload, rebuilt)

            disk_manifest = json.loads((root / "game.pck.chunks.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest, disk_manifest)
            for item in manifest["chunks"]:
                self.assertLessEqual(item["size"], 41)
                self.assertEqual(
                    hashlib.sha256((root / item["file"]).read_bytes()).hexdigest(),
                    item["sha256"],
                )

            html = (root / "index.html").read_text(encoding="utf-8")
            loader = (root / "index.js").read_text(encoding="utf-8")
            worker = (root / "index.service.worker.js").read_text(encoding="utf-8")
            self.assertIn(splitter.HTML_MARKER, html)
            self.assertIn('"game.pck":173', html)
            self.assertIn(splitter.JS_MARKER, loader)
            self.assertIn("fetchChunkedGodotResource(file, fileSize)", loader)
            self.assertNotIn("game.pck", json.loads(
                worker.split("const CACHEABLE_FILES = ", 1)[1].split(";", 1)[0]
            ))
            for item in manifest["chunks"]:
                self.assertIn(item["file"], worker)

            node = shutil.which("node")
            if node:
                node_program = f"""
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
globalThis.__GODOT_PCK_CHUNKS__ = {json.dumps({
    'schema': manifest['schema'],
    'chunkSizeLimit': manifest['chunk_size_limit'],
    'original': manifest['original'],
    'chunks': manifest['chunks'],
}, separators=(',', ':'))};
globalThis.fetch = async (file) => new Response(fs.readFileSync(path.join({json.dumps(str(root))}, file)));
{splitter.STREAM_HELPER}
(async () => {{
  const response = await fetchChunkedGodotResource('game.pck', 173);
  const body = Buffer.from(await response.arrayBuffer());
  const digest = crypto.createHash('sha256').update(body).digest('hex');
  if (body.length !== 173 || digest !== {json.dumps(hashlib.sha256(payload).hexdigest())}) process.exit(7);
}})().catch((error) => {{ console.error(error); process.exit(8); }});
"""
                subprocess.run([node, "-e", node_program], check=True, timeout=20)

    def test_unknown_loader_fails_before_mutating_export(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            payload = make_fixture(root, loader="console.log('not a Godot loader');\n")
            with self.assertRaises(SystemExit):
                splitter.split_export(root, chunk_size=41)
            self.assertEqual(payload, (root / "game.pck").read_bytes())
            self.assertFalse(list(root.glob("*.chunk-*")))
            self.assertNotIn(splitter.HTML_MARKER, (root / "index.html").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
