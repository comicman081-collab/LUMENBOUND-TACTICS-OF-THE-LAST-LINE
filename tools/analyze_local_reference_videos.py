"""Create private, local-only contact sheets from supplied map-reference videos.

This is a build-time review helper.  It never uploads, copies, or packages
the supplied videos.  Outputs belong under work/reference_cache/ and are
excluded from Web/source release packaging.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def _frame_at(capture: cv2.VideoCapture, frame_index: int) -> np.ndarray | None:
    capture.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
    ok, frame = capture.read()
    return frame if ok else None


def _thumbnail(frame: np.ndarray, label: str, target_width: int = 480) -> np.ndarray:
    height, width = frame.shape[:2]
    scale = target_width / max(1, width)
    image = cv2.resize(frame, (target_width, max(1, round(height * scale))), interpolation=cv2.INTER_AREA)
    cv2.rectangle(image, (0, 0), (target_width, 32), (7, 15, 24), -1)
    cv2.putText(image, label, (10, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.56, (225, 239, 245), 1, cv2.LINE_AA)
    return image


def _contact_sheet(frames: list[np.ndarray], labels: list[str]) -> np.ndarray:
    thumbs = [_thumbnail(frame, label) for frame, label in zip(frames, labels)]
    max_height = max(image.shape[0] for image in thumbs)
    padded: list[np.ndarray] = []
    for image in thumbs:
        if image.shape[0] < max_height:
            image = cv2.copyMakeBorder(image, 0, max_height - image.shape[0], 0, 0, cv2.BORDER_CONSTANT, value=(4, 9, 14))
        padded.append(image)
    columns = 3
    blank = np.zeros_like(padded[0])
    rows: list[np.ndarray] = []
    for row_start in range(0, len(padded), columns):
        row = padded[row_start:row_start + columns]
        row += [blank] * (columns - len(row))
        rows.append(np.concatenate(row, axis=1))
    return np.concatenate(rows, axis=0)


def analyze(video_path: Path, output_dir: Path) -> dict:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Cannot decode reference video: {video_path}")
    fps = capture.get(cv2.CAP_PROP_FPS)
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration = frame_count / fps if fps > 0 else 0.0
    fractions = (0.0, 0.18, 0.38, 0.58, 0.78, 0.96)
    indices = [min(max(0, frame_count - 1), round((frame_count - 1) * fraction)) for fraction in fractions]
    frames: list[np.ndarray] = []
    labels: list[str] = []
    for fraction, index in zip(fractions, indices):
        frame = _frame_at(capture, index)
        if frame is None:
            continue
        frames.append(frame)
        labels.append(f"{video_path.stem}  {index / max(fps, 1.0):.1f}s  ({fraction:.0%})")
    capture.release()
    if not frames:
        raise RuntimeError(f"No frames extracted from {video_path}")
    sheet_path = output_dir / f"{video_path.stem}_contact_sheet.jpg"
    cv2.imwrite(str(sheet_path), _contact_sheet(frames, labels), [cv2.IMWRITE_JPEG_QUALITY, 92])
    return {
        "source_path": str(video_path),
        "source_bytes": video_path.stat().st_size,
        "fps": fps,
        "frame_count": frame_count,
        "duration_seconds": duration,
        "width": width,
        "height": height,
        "contact_sheet": str(sheet_path),
        "sampled_seconds": [round(index / max(fps, 1.0), 3) for index in indices],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("videos", nargs="+", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = [analyze(video, args.output) for video in args.videos]
    report_path = args.output / "reference_video_metadata.json"
    report_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(report_path), "videos": results}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
