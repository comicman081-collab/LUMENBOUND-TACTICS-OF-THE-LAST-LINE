"""Local-only temporal crops of the user's combat reference; never runtime art."""
import json
from pathlib import Path
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('C:/Users/AAA/Videos/화면 녹화/화면 녹화 중 2026-09-04 192543.mp4')
OUT = ROOT / 'work/reference_cache/combat_motion_20260907/r2'

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    capture = cv2.VideoCapture(str(SOURCE))
    if not capture.isOpened(): raise RuntimeError('REFERENCE_DECODE_FAILED')
    fps, width, height, count = (capture.get(key) for key in (cv2.CAP_PROP_FPS, cv2.CAP_PROP_FRAME_WIDTH, cv2.CAP_PROP_FRAME_HEIGHT, cv2.CAP_PROP_FRAME_COUNT))
    records = []
    for start in (12.0, 24.0, 41.0, 57.0):
        frames = []
        for step in range(12):
            at = start + step / 12
            capture.set(cv2.CAP_PROP_POS_MSEC, at * 1000)
            ok, frame = capture.read()
            if not ok: raise RuntimeError(f'FRAME_MISSING:{at}')
            h, w = frame.shape[:2]
            # Party and contact lane only, excluding the reference game's HUD.
            crop = frame[round(h*.32):round(h*.82),round(w*.11):round(w*.88)]
            crop = cv2.resize(crop,(480,176),interpolation=cv2.INTER_AREA)
            tile = np.full((202,480,3),(18,28,35),dtype=np.uint8)
            tile[26:]=crop
            cv2.putText(tile,f'{at:.3f}s',(8,18),cv2.FONT_HERSHEY_SIMPLEX,.47,(235,240,235),1,cv2.LINE_AA)
            frames.append(tile)
        sheet = np.vstack([np.hstack(frames[i:i+3]) for i in range(0,12,3)])
        filename = OUT / f'motion_{start:04.1f}s.jpg'
        # OpenCV's Windows narrow-path imwrite silently fails on Korean paths.
        ok, encoded = cv2.imencode('.jpg',sheet,[cv2.IMWRITE_JPEG_QUALITY,95])
        if not ok: raise RuntimeError('CONTACT_SHEET_ENCODE_FAILED')
        filename.write_bytes(encoded.tobytes())
        if not filename.is_file(): raise RuntimeError('CONTACT_SHEET_WRITE_FAILED')
        records.append({'start_seconds':start,'step_seconds':1/12,'frames':12,'sheet':str(filename)})
    capture.release()
    report={'source':str(SOURCE),'fps':fps,'width':width,'height':height,'duration_seconds':count/fps,'method':'local OpenCV frame extraction; no model, upload or copied game assets','runtime_use':False,'records':records}
    (OUT/'analysis_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))

if __name__ == '__main__': main()
