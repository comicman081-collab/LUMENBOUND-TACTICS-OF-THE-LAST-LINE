"""Contact sheets for a real local QA recording, not generated game assets."""
import argparse
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('video', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
source, output = args.video.resolve(), args.output.resolve()
if not source.is_relative_to(ROOT) or not output.is_relative_to(ROOT):
    raise ValueError('Project local input/output only')
if output.exists(): raise ValueError('Retain previous review; choose a new output')
output.mkdir(parents=True)
cap = cv2.VideoCapture(str(source))
if not cap.isOpened(): raise RuntimeError('Recording decode failed')
fps = cap.get(cv2.CAP_PROP_FPS)
# Browser MediaRecorder WebM has no seek/duration index. Decode once in
# timestamp order instead of trusting FFmpeg's negative unknown frame count.
targets=sorted((start,index,start+index/8) for start in (2.,13.,26.,39.) for index in range(12))
selected={}
cursor=0
duration=0.
while True:
    ok,frame=cap.read()
    if not ok: break
    duration=max(duration,cap.get(cv2.CAP_PROP_POS_MSEC)/1000)
    while cursor<len(targets) and duration>=targets[cursor][2]:
        start,index,_=targets[cursor]
        selected[(start,index)]=frame.copy()
        cursor+=1
cap.release()
if duration<=0 or len(selected)<12: raise RuntimeError('No valid decoded motion sequence')
records=[]
for start in (2., 13., 26., 39.):
    if start + 1.5 >= duration: continue
    frames=[]
    for index in range(12):
        at=start+index/8
        frame=selected.get((start,index))
        if frame is None: raise RuntimeError(f'Missing actual frame {at}')
        h,w=frame.shape[:2]
        frame=frame[round(h*.52):round(h*.86)]
        frame=cv2.resize(frame,(390,286),interpolation=cv2.INTER_AREA)
        tile=np.full((312,390,3),(18,28,35),dtype=np.uint8)
        tile[26:]=frame
        cv2.putText(tile,f'{at:.3f}s',(8,18),cv2.FONT_HERSHEY_SIMPLEX,.48,(240,240,240),1,cv2.LINE_AA)
        frames.append(tile)
    sheet=np.vstack([np.hstack(frames[i:i+4]) for i in range(0,12,4)])
    ok,encoded=cv2.imencode('.jpg',sheet,[cv2.IMWRITE_JPEG_QUALITY,96])
    if not ok: raise RuntimeError('Encode failed')
    target=output/f'combat_{int(start):02}.jpg'
    target.write_bytes(encoded.tobytes())
    records.append({'start':start,'frames':12,'step_seconds':.125,'path':str(target)})
report={'source':str(source),'source_sha256':hashlib.file_digest(source.open('rb'),'sha256').hexdigest(),
        'container_reported_fps_unreliable_for_webm':fps,'duration':duration,'records':records,
        'method':'Local OpenCV decode of real gameplay video. No model, no artwork generation.'}
(output/'review_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
