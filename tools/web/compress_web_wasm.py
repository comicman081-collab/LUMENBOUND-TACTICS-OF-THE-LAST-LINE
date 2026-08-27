"""Compress the generated Godot Web WASM in-place for Sites' file limit.

The Sites connector limits each uploaded member to 25 MiB. Godot's standard
WASM template is larger than that, so the build keeps the stable `.wasm` name
but stores gzip bytes and adds a tiny DecompressionStream path to the generated
loader. This is build-time packaging only; the browser still receives a normal
WASM Response before WebAssembly instantiation.
"""
from __future__ import annotations

import gzip
import re
import sys
from pathlib import Path


LOADER_NEEDLE = "return fetch(file).then(function (response) {"
LOADER_PATCH = """return fetch(file).then(async function (response) {
\t\t\tif (file.endsWith('.wasm') && response.ok) {
\t\t\t\tif (typeof DecompressionStream !== 'undefined') {
\t\t\t\t\tconst decoded = response.body.pipeThrough(new DecompressionStream('gzip'));
\t\t\t\t\tresponse = new Response(decoded, {status: response.status, headers: {'content-type': 'application/wasm'}});
\t\t\t\t} else if (globalThis.pako?.ungzip) {
\t\t\t\t\tconst decoded = globalThis.pako.ungzip(new Uint8Array(await response.arrayBuffer()));
\t\t\t\t\tresponse = new Response(decoded, {status: response.status, headers: {'content-type': 'application/wasm'}});
\t\t\t\t} else {
\t\t\t\t\tthrow new Error('WASM gzip decompression is unavailable in this browser');
\t\t\t\t}
\t\t\t}
"""

# Godot's progress loader and Emscripten's WebAssembly bootstrap fetch the
# executable independently.  Patching only `loadFetch()` leaves the bootstrap
# feeding gzip bytes directly to `instantiateStreaming()`, which fails with a
# WASM magic-word error on an ordinary static HTTP server.  Keep this exact
# generated-loader contract guarded so an engine template change fails the
# build instead of producing a non-starting package.
EMSCRIPTEN_INSTANTIATE_NEEDLE = (
    'var response=fetch(binaryFile,{credentials:"same-origin"});'
    'var instantiationResult=await WebAssembly.instantiateStreaming(response,imports);'
)
EMSCRIPTEN_INSTANTIATE_PATCH = (
    'var response=await fetch(binaryFile,{credentials:"same-origin"});'
    'if(/\\.wasm(?:[?#]|$)/.test(binaryFile)&&response.ok){'
    'if(typeof DecompressionStream!=="undefined"){'
    'const decoded=response.body.pipeThrough(new DecompressionStream("gzip"));'
    'response=new Response(decoded,{status:response.status,headers:{"content-type":"application/wasm"}});'
    '}else if(globalThis.pako?.ungzip){'
    'const decoded=globalThis.pako.ungzip(new Uint8Array(await response.arrayBuffer()));'
    'response=new Response(decoded,{status:response.status,headers:{"content-type":"application/wasm"}});'
    '}else{throw new Error("WASM gzip decompression is unavailable in this browser")}'
    '}'
    'var instantiationResult=await WebAssembly.instantiateStreaming(response,imports);'
)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: compress_web_wasm.py <web-release-directory>")
    root = Path(sys.argv[1]).resolve()
    wasm_candidates = sorted(root.glob("*.wasm"))
    if len(wasm_candidates) != 1:
        raise SystemExit(f"expected exactly one WASM file in {root}, found {len(wasm_candidates)}")
    wasm = wasm_candidates[0]
    raw = wasm.read_bytes()
    if raw[:4] != b"\x00asm":
        raise SystemExit(f"WASM magic missing before compression: {wasm}")
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    if len(compressed) >= 26_214_400:
        raise SystemExit(f"compressed WASM remains above 25 MiB: {len(compressed)}")
    temp = wasm.with_suffix(".wasm.tmp")
    temp.write_bytes(compressed)
    temp.replace(wasm)

    js_path = root / "index.js"
    loader = js_path.read_text(encoding="utf-8")
    if LOADER_NEEDLE not in loader:
        raise SystemExit("Godot loader fetch hook not found; refusing an unverified WASM package")
    loader = loader.replace(LOADER_NEEDLE, LOADER_PATCH, 1)
    if loader.count(EMSCRIPTEN_INSTANTIATE_NEEDLE) != 1:
        raise SystemExit(
            "Godot Emscripten instantiate hook not found exactly once; "
            "refusing a gzip package that cannot bootstrap"
        )
    loader = loader.replace(
        EMSCRIPTEN_INSTANTIATE_NEEDLE,
        EMSCRIPTEN_INSTANTIATE_PATCH,
        1,
    )

    html_path = root / "index.html"
    html = html_path.read_text(encoding="utf-8")
    pako_path = root / "pako_inflate.min.js"
    if not pako_path.is_file():
        raise SystemExit("pako inflate fallback is missing from the Web staging directory")
    pako_source = pako_path.read_text(encoding="utf-8")
    # Keep the fallback in the same execution context as the Godot loader. In
    # some embedded browsers the page and loader globals are isolated, so an
    # external or HTML-inline script is not reliably visible to the loader.
    if "pako 0.2.9 nodeca/pako" not in loader:
        loader = pako_source + "\n" + loader
    js_path.write_text(loader, encoding="utf-8", newline="\n")
    pako_path.unlink()
    wasm_key = re.escape(wasm.name)
    html, count = re.subn(rf'("{wasm_key}":)\d+', rf'\g<1>{len(compressed)}', html, count=1)
    if count != 1:
        raise SystemExit(f"WASM file size entry not found in {html_path}")
    # Keep the loader URL identical to Godot's service-worker cache key. The
    # outer build script rotates CACHE_VERSION from the final PCK/WASM/JS/HTML
    # hashes after every post-export transform, so a query-string cache buster
    # here would break offline PWA loading.
    if len(re.findall(r'<script\s+src="index\.js"\s*></script>', html)) != 1:
        raise SystemExit(f"index.js script tag not found in {html_path}")
    html_path.write_text(html, encoding="utf-8", newline="\n")
    print(f"WEB_WASM_RAW_BYTES={len(raw)}")
    print(f"WEB_WASM_GZIP_BYTES={len(compressed)}")
    print("WEB_WASM_COMPRESSION=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
