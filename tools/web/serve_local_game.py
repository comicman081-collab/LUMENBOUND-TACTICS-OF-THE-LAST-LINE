"""Detached localhost game server with a browser-readable intro preview."""
import argparse
import hashlib
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sys
import socket
import html
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
# The game requests /intro.mp4. Serve the same verified browser-compatible
# 1080p/50s clip used by the published build; retain the old video originals.
INTRO = ROOT / 'intro/web_1080p_50s/intro.mp4'
SERVICE = 'lumenbound-local-player-v2'

def reviewed_art():
    assets = {}
    for folder in ['enemy_replacements_20260911','roster_replacements_20260911']:
        root = ROOT/'data_source/art_source'/folder
        manifest = root/'manifest.json'
        if not manifest.is_file(): continue
        document = json.loads(manifest.read_text(encoding='utf8'))
        if document.get('status') != 'LOCAL_VISUAL_REVIEW_PASS': continue
        for row in document['assets']:
            source = (root/row['file']).resolve()
            if row.get('review') == 'PASS' and source.is_relative_to(root.resolve()):
                assets[row['entity_id']] = source
    return assets

def art_gallery():
    cards = []
    for entity in sorted(reviewed_art(),key=lambda e:('0' if e.startswith('CHR') else '2' if e.startswith('BOSS') else '1')+e):
        group = '캐릭터' if entity.startswith('CHR') else '보스' if entity.startswith('BOSS') else '몹'
        cards.append(f'<article data-group="{group}"><a href="/art/{entity}.png" target="_blank"><img loading="lazy" src="/art/{entity}/preview.png" alt="{entity}"></a><b>{entity}</b><span>{group}</span><a href="/art/{entity}.png" download>원화 저장</a></article>')
    return '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LUMENBOUND 원화</title>
<style>*{box-sizing:border-box}body{margin:0;background:#0a1520;color:#e7f1f4;font:16px system-ui}main{max-width:1440px;margin:auto;padding:32px}h1{margin-bottom:8px}p{color:#a8bac8}nav{display:flex;gap:12px;margin:24px 0;flex-wrap:wrap}button,a{color:#87e7d6}button{background:#203444;border:1px solid #53717d;border-radius:22px;padding:10px 22px;cursor:pointer;font:inherit}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:18px}article{background:#162837;border-radius:14px;overflow:hidden;padding:14px}img{display:block;width:100%;aspect-ratio:1;object-fit:contain;background:radial-gradient(#304854,#172633);border-radius:8px}b,span,article>a:last-child{display:block;margin-top:8px}span{color:#9aafb9;font-size:13px}</style>
<main><a href="/">게임 실행</a><h1>새로운 전투 원화</h1><p>캐릭터 8명 · 몹 42종 · 보스 23종. 그림을 누르면 고해상도 원본을 볼 수 있습니다.</p><nav>''' + ''.join(f'<button onclick="document.querySelectorAll(\'article\').forEach(a=>a.hidden=this.textContent!==\'전체\' &amp;&amp; a.dataset.group!==this.textContent)">{html.escape(g)}</button>' for g in ['전체','캐릭터','몹','보스']) + '</nav><section>' + ''.join(cards) + '</section></main></html>'
PREVIEW = '''<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LUMENBOUND · 인트로 영상</title>
<style>body{margin:0;background:#080d14;color:#edf5ff;font:16px system-ui}
main{max-width:1280px;margin:auto;padding:24px}video{width:100%;background:#000}
a{color:#80e5d1}nav{display:flex;gap:24px;margin:16px 0}</style>
<main><h1>인트로 · 1080p / 50초</h1>
<video controls playsinline preload="metadata" src="/intro.mp4"></video>
<nav><a href="/">게임 실행</a><a href="/intro.mp4" download="intro_1080p_50s.mp4">영상 저장</a></nav></main></html>'''


class LocalHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = False

    def server_bind(self):
        # Windows SO_REUSEADDR allows two different builds to claim one port.
        # Requests then land on an arbitrary old server. Claim it exclusively.
        if os.name == 'nt':
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, build, play_path, **kwargs):
        self.build = build
        self.play_path = play_path
        super().__init__(*args, directory=str(build), **kwargs)

    def do_GET(self):
        self._request(False)

    def do_HEAD(self):
        self._request(True)

    def _request(self, head):
        route = urlsplit(self.path).path
        if route == '/':
            # A build-specific URL keeps old PWA/cache entries from mixing old
            # game packs with the current HTML, without clearing player saves.
            self.send_response(307)
            query = urlsplit(self.path).query
            self.send_header('Location', self.play_path + ('?' + query if query else ''))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif route.startswith(self.play_path):
            self.path = self.path.replace(self.play_path, '/', 1)
            if head:
                super().do_HEAD()
            else:
                super().do_GET()
        elif route == '/__local_game_status':
            body = json.dumps({'service': SERVICE, 'build': self.build.relative_to(ROOT).as_posix(),
                               'pid': os.getpid(), 'play_path': self.play_path}).encode()
            self._body(body, 'application/json', head)
        elif route in ('/intro-preview', '/intro-preview/'):
            self._body(PREVIEW.replace('href="/"', f'href="{self.play_path}"').encode(), 'text/html; charset=utf-8', head)
        elif route == '/intro.mp4':
            self._intro(head)
        elif route in ('/art-gallery','/art-gallery/'):
            self._body(art_gallery().encode('utf8'),'text/html; charset=utf-8',head)
        elif route.startswith('/art/'):
            match = re.fullmatch(r'/art/((?:CHR|ENM|BOSS)\d{3})(\.png|/preview\.png)',route)
            assets = reviewed_art()
            if not match or match[1] not in assets:
                self.send_error(404,'Reviewed artwork not found')
                return
            source = assets[match[1]] if match[2]=='.png' else ROOT/'godot/assets/runtime_web/combat'/match[1]/'preview.png'
            self._body(source.read_bytes(),'image/png',head)
        elif head:
            super().do_HEAD()
        else:
            super().do_GET()

    def _body(self, body, kind, head):
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def _intro(self, head):
        if not INTRO.is_file():
            self.send_error(404, 'Completed intro missing')
            return
        size = INTRO.stat().st_size
        start, end = 0, size - 1
        requested = self.headers.get('Range')
        if requested:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested.strip())
            valid = match and any(match.groups())
            if valid:
                left, right = match.groups()
                start = int(left) if left else max(0, size - int(right))
                end = min(size - 1, int(right)) if left and right else size - 1
                valid = 0 <= start <= end < size
            if not valid:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
        count = end - start + 1
        self.send_response(206 if requested else 200)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Content-Length', str(count))
        self.send_header('Accept-Ranges', 'bytes')
        if requested:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        if not head:
            try:
                with INTRO.open('rb') as video:
                    video.seek(start)
                    while count:
                        block = video.read(min(count, 1024 * 1024))
                        if not block:
                            break
                        self.wfile.write(block)
                        count -= len(block)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass  # Closing/seeking a browser video cancels an old range.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8770)
    parser.add_argument('--log-file', type=Path)
    args = parser.parse_args()
    if args.log_file:
        log_file = args.log_file.resolve()
        if not log_file.is_relative_to(ROOT / 'reports' / 'local_launcher'):
            raise ValueError('Server logs must stay in this project launcher report folder')
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_stream = log_file.open('a', encoding='utf-8', buffering=1)
        sys.stdout = log_stream
        sys.stderr = log_stream
    build = args.build.resolve()
    if not build.is_relative_to(ROOT / 'builds') or not (build / 'index.html').is_file():
        raise ValueError('Choose a completed Web build under this project')
    # R7 exports content-hash the large runtime pair (for example
    # ``r7_current_<hash>.pck``) so the browser service worker cannot retain a
    # stale pack. Older exports still use ``index.pck``. Resolve either form
    # instead of making the local launcher fail before it can serve the build.
    pck_path = build / 'index.pck'
    if not pck_path.is_file():
        candidates = sorted(build.glob('*.pck'))
        if len(candidates) != 1:
            raise ValueError(f'Expected exactly one Web runtime PCK in {build}; found {len(candidates)}')
        pck_path = candidates[0]
    with pck_path.open('rb') as pack:
        build_id = hashlib.file_digest(pack, 'sha256').hexdigest()[:12]
    server = LocalHTTPServer(('127.0.0.1', args.port), partial(Handler, build=build, play_path=f'/play/{build_id}/'))
    print(f'{SERVICE} http://127.0.0.1:{args.port}/ build={build.name}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
