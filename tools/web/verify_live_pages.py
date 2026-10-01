"""Verify the live GitHub Pages deployment byte for byte against its own VERSION.json / audio_sidecars.json.

usage: verify_live_pages.py <base_url> [workers]
Streams every file listed in the live VERSION.json and audio_sidecars.json (plus the PCK), hashes it on the fly
(nothing is stored), and reports size/hash mismatches, HTTP statuses and the response headers that matter for the Web
build (content type, byte ranges for the movie). Run it after each deployment; it exits 0 only on LIVE_VERIFY=PASS.
"""
import hashlib
import json
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

base = sys.argv[1].rstrip("/") + "/"
workers = int(sys.argv[2]) if len(sys.argv) > 2 else 8
stamp = str(int(time.time()))
lock = threading.Lock()
problems = []
stats = {"files": 0, "bytes": 0}
headers_seen = {}


def url_for(name: str) -> str:
    return base + "/".join(urllib.parse.quote(part) for part in name.split("/")) + "?v=" + stamp


def fetch_hash(name: str, expected_bytes: int, expected_sha: str) -> None:
    last_error = ""
    for attempt in range(4):
        try:
            request = urllib.request.Request(url_for(name), headers={"User-Agent": "lumenbound-verify/1"})
            digest = hashlib.sha256()
            size = 0
            with urllib.request.urlopen(request, timeout=60) as response:
                if name.endswith((".wasm", ".pck", ".mp4", "index.html", ".json")) and name not in headers_seen:
                    with lock:
                        headers_seen[name] = {key: response.headers.get(key) for key in ("Content-Type", "Content-Length", "Content-Encoding", "Accept-Ranges", "Cache-Control")}
                while True:
                    block = response.read(1 << 20)
                    if not block:
                        break
                    digest.update(block)
                    size += len(block)
            with lock:
                stats["files"] += 1
                stats["bytes"] += size
                if size != expected_bytes or digest.hexdigest() != expected_sha:
                    problems.append(f"MISMATCH {name}: bytes {size} vs {expected_bytes}, sha {digest.hexdigest()[:12]} vs {expected_sha[:12]}")
            return
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last_error = repr(error)
            time.sleep(1.5 * (attempt + 1))
    with lock:
        problems.append(f"FETCH-FAILED {name}: {last_error}")


def get_json(name: str):
    with urllib.request.urlopen(urllib.request.Request(url_for(name), headers={"User-Agent": "lumenbound-verify/1"}), timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


started = time.time()
version = get_json("VERSION.json")
audio = get_json("audio_sidecars.json")
files = version["files"]
sidecars = {}
for key in ("tracks", "sfx", "voice"):
    sidecars.update(audio.get(key, {}))
base_name = version["runtime_artifact_base"]
work = [(name, record["bytes"], record["sha256"]) for name, record in files.items()]
work += [(name, record["bytes"], record["sha256"]) for name, record in sidecars.items()]
work.append((f"{base_name}.pck", version["pck_size"], version["pck_sha256"]))
print(f"live VERSION.json: deployment_commit={version.get('deployment_commit')} payload_commit={version.get('payload_commit')} deployed_utc={version.get('deployed_utc')}")
print(f"checking {len(work)} files with {workers} workers ...", flush=True)
with ThreadPoolExecutor(max_workers=workers) as pool:
    for item in work:
        pool.submit(fetch_hash, *item)

# byte ranges for the movie and the optional HD folder fallback
range_note = ""
try:
    request = urllib.request.Request(url_for("intro.mp4"), headers={"Range": "bytes=0-99", "User-Agent": "lumenbound-verify/1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        range_note = f"intro.mp4 Range -> {response.status} {response.headers.get('Content-Range')} len={len(response.read())}"
except Exception as error:  # noqa: BLE001
    range_note = f"intro.mp4 Range failed: {error!r}"
hd_note = ""
try:
    with urllib.request.urlopen(urllib.request.Request(base + "_hd/none.png?v=" + stamp), timeout=30) as response:
        hd_note = f"_hd probe -> {response.status}"
except urllib.error.HTTPError as error:
    hd_note = f"_hd probe -> {error.code}"
absolute_note = ""
try:
    host = urllib.parse.urlsplit(base)
    with urllib.request.urlopen(f"{host.scheme}://{host.netloc}/intro.mp4?v={stamp}", timeout=30) as response:
        absolute_note = f"ROOT /intro.mp4 -> {response.status}"
except urllib.error.HTTPError as error:
    absolute_note = f"ROOT /intro.mp4 -> {error.code} (expected: the shim rewrites it to the project path)"

print(json.dumps({"files_checked": stats["files"], "bytes_checked": stats["bytes"], "seconds": round(time.time() - started, 1), "problems": len(problems)}))
for note in (range_note, hd_note, absolute_note):
    print(note)
print(json.dumps(headers_seen, indent=1))
for line in problems[:30]:
    print(line)
passed = not problems and stats["files"] == len(work)
print("LIVE_VERIFY=" + ("PASS" if passed else "FAIL"))
sys.exit(0 if passed else 1)
