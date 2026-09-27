"""Japanese story voice pipeline (text stays Korean on screen, voices are Japanese only).

Steps (each is resumable and writes only inside the project):
  extract   scenarios + chapter-map pages (first meetings, anomalies, bosses, incidents) + ko.csv
            -> data_source/voice/ja/lines_base.json (one entry per unique speaker+line)
  jobs      lines_base + translation_ja.json + voice_cast_ja.json -> work/voice_ja/jobs.jsonl
  run       jobs.jsonl -> raw WAV takes through the alibaba-token-plan helper (Token Plan, Singapore host)
  qa        raw WAV -> faster-whisper Japanese transcripts + timing/level stats -> work/voice_ja/qa.json
  select    QA reports of every take -> selection.json (best unflagged take per line; overrides win)
  finalize  approved takes -> trimmed, loudness-matched OGG in godot/assets/audio/voice/ja/ + voice_manifest.json

Narration and character dialogue are voiced; the player's choice buttons are not (the protagonist is unvoiced).
The API key is read only by the helper; this script never touches it.
"""
import argparse, csv, glob, hashlib, json, os, pathlib, re, shutil, struct, subprocess, sys, tempfile, threading, time, unicodedata
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "data_source" / "voice" / "ja"
WORK = ROOT / "work" / "voice_ja_20260927"
RAW = WORK / "raw"
OUT = ROOT / "godot" / "assets" / "audio" / "voice" / "ja"
HELPER = pathlib.Path.home() / ".claude" / "skills" / "alibaba-token-plan" / "scripts" / "alibaba_token_plan.py"
BASE_URL = "https://token-plan.ap-southeast-1.maas.aliyuncs.com"
MODEL = "qwen-audio-3.0-tts-plus"
FFMPEG = r"C:\AI_SHARED\common_tools\ffmpeg\bin\ffmpeg.exe"
VOICED = ("dialogue", "narration")
LOCK = threading.Lock()


def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def write_json(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- extract

def _map_pages(definition):
    """Voiced map dialogue: (source id, page) for every authored page with a speaker key."""
    chapter = definition.get("chapter_id", "")
    for event in definition.get("event_encounters", []):
        for page in event.get("pre_battle_dialogue", []):
            yield f"{chapter}:{event['event_encounter_id']}", page
    for node in definition.get("nodes", []):
        for page in node.get("presentation", {}).get("pre_battle_dialogue", []):
            yield f"{chapter}:{node['node_id']}", page
    for incident in definition.get("incidents", []):
        for page in incident.get("lines", []):
            yield f"{chapter}:{incident['incident_id']}", page


def extract(_args):
    ko = {r["key"]: r["text"] for r in csv.DictReader(open(ROOT / "data_source/localization/ko.csv", encoding="utf-8-sig"))}
    entries, by_line = [], {}

    def add(speaker_key, text_key, kind, source):
        text = ko[text_key]
        key = (speaker_key, text)
        if key not in by_line:
            by_line[key] = {"voice_id": "vo_" + text_key.lower(), "speaker_key": speaker_key,
                            "speaker_ko": ko.get(speaker_key, speaker_key), "kind": kind,
                            "ko": text, "first_scenario": source, "text_keys": []}
            entries.append(by_line[key])
        if text_key not in by_line[key]["text_keys"]:
            by_line[key]["text_keys"].append(text_key)

    for path in sorted(glob.glob(str(ROOT / "data_source/scenarios/*.json"))):
        scenario = load_json(path)
        for command in scenario["commands"]:
            if command.get("command") in VOICED:
                add(command.get("speaker_key", ""), command["text_key"], command["command"], scenario["id"])
    # Map pages without a speaker key are legacy generated notices and stay unvoiced.
    for path in sorted(glob.glob(str(ROOT / "godot/data/compiled/chapter_maps/*.json"))):
        for source, page in _map_pages(load_json(path)):
            if page.get("speaker_key") and page.get("text_key") in ko:
                kind = "narration" if page.get("speaker_kind") == "NARRATION" else "dialogue"
                add(page["speaker_key"], page["text_key"], kind, source)
    write_json(SRC / "lines_base.json", {"schema_version": 1, "generated_by": "tools/voice/voice_ja_pipeline.py extract",
                                         "lines": entries})
    print(json.dumps({"unique_lines": len(entries), "text_keys": sum(len(e["text_keys"]) for e in entries)}))


# ---------------------------------------------------------------- jobs

def tts_text(ja, readings):
    """Coined world terms are sent with their kana reading so the voice does not guess an on/kun reading."""
    for word, kana in sorted(readings.items(), key=lambda kv: -len(kv[0])):
        ja = ja.replace(word, kana)
    return ja


def profile_for(cast, speaker_key):
    """Exact speaker first; boss/anomaly keys share a prefix profile (ENEMY_*)."""
    if speaker_key in cast["speakers"]:
        return cast["speakers"][speaker_key]
    for prefix, profile in cast.get("prefix_speakers", {}).items():
        if speaker_key.startswith(prefix):
            return profile
    raise KeyError(f"no voice cast for {speaker_key}")


def translation_for(translation, line):
    """A line's own entry wins; lines repeated across chapters share one entry keyed by the Korean text."""
    return translation["lines"].get(line["voice_id"]) or translation.get("by_ko", {}).get(line["ko"])


def jobs(args):
    base = load_json(SRC / "lines_base.json")["lines"]
    translation = load_json(SRC / "translation_ja.json")
    cast = load_json(SRC / "voice_cast_ja.json")
    readings = translation.get("readings", {})
    rows, missing = [], []
    take = args.take
    for line in base:
        tr = translation_for(translation, line)
        if not tr or not tr.get("ja"):
            missing.append(line["voice_id"])
            continue
        profile = profile_for(cast, line["speaker_key"])
        # Readings also cover hand-written tts overrides, which usually fix only a number.
        text = tts_text(tr.get("tts") or tr["ja"], readings)
        instruction = profile["instruction"]
        if tr.get("direction"):
            # "<language>. <persona>. <delivery>" -> the line's direction replaces the default delivery.
            language, persona = instruction.split(". ")[:2]
            instruction = f"{language}. {persona}. {tr['direction']}"
        rows.append({"id": line["voice_id"], "voice": "qwen-audio-3.0-tts-plus-" + profile["voice"], "text": text,
                     "ja": tr["ja"], "instruction": instruction[:100], "speaker_key": line["speaker_key"],
                     "out": str(RAW / f"take{take}" / f"{line['voice_id']}.wav")})
    if missing:
        raise SystemExit(f"untranslated lines: {len(missing)} e.g. {missing[:5]}")
    WORK.mkdir(parents=True, exist_ok=True)
    only = set(pathlib.Path(args.ids).read_text(encoding="utf-8").split()) if args.ids else None
    selected = [r for r in rows if only is None or r["id"] in only]
    out = WORK / f"jobs_take{take}.jsonl"
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in selected), encoding="utf-8")
    print(json.dumps({"jobs": len(selected), "file": str(out)}))


# ---------------------------------------------------------------- run

def _fix_wav_header(path):
    """The service streams WAV with placeholder RIFF/data sizes; rewrite them to the real lengths."""
    b = bytearray(pathlib.Path(path).read_bytes())
    if b[:4] != b"RIFF":
        raise ValueError("not a RIFF file")
    i = b.find(b"data")
    data_len = len(b) - (i + 8)
    if data_len % 2:
        b = b[:-1]
        data_len -= 1
    struct.pack_into("<I", b, 4, len(b) - 8)
    struct.pack_into("<I", b, i + 4, data_len)
    pathlib.Path(path).write_bytes(bytes(b))
    return data_len / 48000.0


def _run_one(job, log_path, tries=4):
    out = pathlib.Path(job["out"])
    if out.exists():
        return "skip"
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="tts_", dir=out.parent))
    txt = tmp / "text.txt"
    txt.write_text(job["text"], encoding="utf-8")
    cmd = [sys.executable, str(HELPER), "tts", "--model", MODEL, "--base-url", BASE_URL, "--voice", job["voice"],
           "--text-file", str(txt), "--format", "wav", "--sample-rate", "24000", "--output-dir", str(tmp),
           "--timeout-ms", "120000"]
    if job.get("instruction"):
        cmd += ["--instruction", job["instruction"]]
    err = ""
    for attempt in range(1, tries + 1):
        started = time.time()
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        wavs = list(tmp.glob("tts_*.wav"))
        if proc.returncode == 0 and wavs:
            seconds = _fix_wav_header(wavs[0])
            shutil.move(str(wavs[0]), str(out))
            shutil.rmtree(tmp, ignore_errors=True)
            with LOCK, open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({"id": job["id"], "status": "ok", "attempt": attempt, "dur": round(seconds, 2),
                                    "sec": round(time.time() - started, 1)}) + "\n")
            return "ok"
        err = (proc.stderr or proc.stdout or "")[-300:]
        for w in wavs:
            w.unlink(missing_ok=True)
        if "Quota" in err or "quota" in err or "Arrearage" in err:
            break
        time.sleep(min(30, 3 * attempt * attempt))
    shutil.rmtree(tmp, ignore_errors=True)
    with LOCK, open(log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({"id": job["id"], "status": "fail", "error": err}, ensure_ascii=False) + "\n")
    return "fail"


def run(args):
    rows = [json.loads(l) for l in open(args.jobs, encoding="utf-8") if l.strip()]
    log_path = str(pathlib.Path(args.jobs).with_suffix(".log.jsonl"))
    counts = {"ok": 0, "skip": 0, "fail": 0}
    with ThreadPoolExecutor(args.workers) as pool:
        for result in pool.map(lambda j: _run_one(j, log_path), rows):
            counts[result] += 1
            done = sum(counts.values())
            if done % 25 == 0 or done == len(rows):
                print(f"{done}/{len(rows)} {counts}", flush=True)
    print(json.dumps(counts))


# ---------------------------------------------------------------- qa

KANA_ONLY = re.compile(r"[^\u3040-\u30ff\u4e00-\u9fff\uff66-\uff9dA-Za-z0-9]")


KANJI_DIGITS = "〇一二三四五六七八九"
STYLE_PROMPT = "今日は天気が良いので、公園を散歩しました。"
DIGIT_RUN = re.compile(r"[0-9][0-9,]*")


def _kanji_below_10000(n):
    text = ""
    for value, unit in ((1000, "千"), (100, "百"), (10, "十")):
        q, n = divmod(n, value)
        if q:
            text += ("" if q == 1 else KANJI_DIGITS[q]) + unit
    return text + (KANJI_DIGITS[n] if n else "")


def _kanji_number(n):
    if n == 0:
        return "零"
    text = ""
    for value, unit in ((10 ** 8, "億"), (10 ** 4, "万")):
        if n >= value:
            text += _kanji_below_10000(n // value) + unit
            n %= value
    return text + _kanji_below_10000(n)


def _norm(text):
    # Whisper writes numbers as digits ("4,311") where the script spells them in kanji.
    text = unicodedata.normalize("NFKC", text)
    text = DIGIT_RUN.sub(lambda m: _kanji_number(int(m.group().replace(",", ""))), text)
    # Katakana and hiragana spell the same sound (coined names come back as トウロダン).
    text = "".join(chr(ord(ch) - 0x60) if "ァ" <= ch <= "ヶ" else ch for ch in text)
    return KANA_ONLY.sub("", text).lower()


def _cer(ref, hyp):
    a, b = _norm(ref), _norm(hyp)
    if not a:
        return 0.0
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (x != y))
    return d[len(b)] / len(a)


def _stats(path):
    import numpy as np
    import wave
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype("float32") / 32768.0
    frame = int(rate * 0.02)
    usable = len(pcm) // frame * frame
    rms = np.sqrt(np.mean(pcm[:usable].reshape(-1, frame) ** 2, axis=1) + 1e-12) if usable else np.zeros(1)
    voiced = np.where(20 * np.log10(rms) > -45)[0]
    lead = (voiced[0] * 0.02) if voiced.size else 0.0
    trail = ((len(rms) - 1 - voiced[-1]) * 0.02) if voiced.size else 0.0
    return {"dur": round(len(pcm) / rate, 2), "lead": round(float(lead), 2), "trail": round(float(trail), 2),
            "peak": round(float(np.max(np.abs(pcm))) if pcm.size else 0.0, 3),
            "clip": int(np.sum(np.abs(pcm) > 0.999))}


def qa(args):
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    if args.dll_dir:
        # CUDA/cuDNN DLLs borrowed read-only from another local environment (e.g. a torch/lib folder).
        os.add_dll_directory(args.dll_dir)
        os.environ["PATH"] = args.dll_dir + os.pathsep + os.environ["PATH"]
    from faster_whisper import WhisperModel
    rows = [json.loads(l) for l in open(args.jobs, encoding="utf-8") if l.strip()]
    model = WhisperModel(args.model, device=args.device, compute_type="float16" if args.device == "cuda" else "int8")
    report = load_json(args.out) if pathlib.Path(args.out).exists() else {}
    for row in rows:
        wav = pathlib.Path(row["out"])
        known = report.get(row["id"], {})
        fresh = known.get("file") == str(wav) and not args.force
        if not wav.exists() or (fresh and not (args.recheck and known["cer"] > args.threshold and "asr_styled" not in known)):
            continue
        entry = known if fresh else None
        if entry is None:
            # No initial prompt: a prompt of the expected text would bias Whisper toward "hearing" it.
            segments, info = model.transcribe(str(wav), language="ja", beam_size=5)
            heard = "".join(s.text for s in segments).strip()
            entry = {"file": str(wav), "tts": row["text"], "ja": row["ja"], "asr": heard,
                     "cer_ja": round(_cer(row["ja"], heard), 3),
                     "cer_tts": round(_cer(row["text"], heard), 3), **_stats(wav)}
            entry["cer"] = min(entry["cer_ja"], entry["cer_tts"])
        if entry["cer"] > args.threshold:
            # Whisper sometimes answers in plain hiragana, which scores as a mismatch against kanji.
            # A neutral sentence (never the expected text) steers it back to ordinary orthography.
            segments, info = model.transcribe(str(wav), language="ja", beam_size=5, initial_prompt=STYLE_PROMPT)
            styled = "".join(s.text for s in segments).strip()
            entry["asr_styled"] = styled
            styled_cer = min(_cer(row["ja"], styled), _cer(row["text"], styled))
            if styled_cer < entry["cer"]:
                entry.update(asr=styled, cer_ja=round(_cer(row["ja"], styled), 3),
                             cer_tts=round(_cer(row["text"], styled), 3))
                entry["cer"] = min(entry["cer_ja"], entry["cer_tts"])
        entry["flag"] = entry["cer"] > args.threshold or entry["clip"] > 0 or entry["dur"] < 0.6
        report[row["id"]] = entry
        write_json(args.out, report)
    flagged = sorted(k for k, v in report.items() if v["flag"])
    print(json.dumps({"checked": len(report), "flagged": len(flagged), "ids": flagged[:40]}, ensure_ascii=False))


def rescore(args):
    """Recompute error rates from the stored transcripts after a normalisation change."""
    report = load_json(args.report)
    for entry in report.values():
        entry["cer_ja"] = round(_cer(entry["ja"], entry["asr"]), 3)
        entry["cer_tts"] = round(_cer(entry["tts"], entry["asr"]), 3)
        entry["cer"] = min(entry["cer_ja"], entry["cer_tts"])
        entry["flag"] = entry["cer"] > args.threshold or entry["clip"] > 0 or entry["dur"] < 0.6
    write_json(args.report, report)
    flagged = sorted(k for k, v in report.items() if v["flag"])
    print(json.dumps({"checked": len(report), "flagged": len(flagged)}))


# ---------------------------------------------------------------- select

def select(args):
    ids = [line["voice_id"] for line in load_json(SRC / "lines_base.json")["lines"]]
    candidates = {}
    for report_path in args.reports:
        for voice_id, entry in load_json(report_path).items():
            if pathlib.Path(entry["file"]).exists():
                candidates.setdefault(voice_id, []).append(entry)
    # Manual picks after listening or reading the transcripts: voice_id -> raw wav path.
    overrides = load_json(args.overrides) if args.overrides and pathlib.Path(args.overrides).exists() else {}
    selection, flagged = {}, []
    for voice_id in ids:
        if voice_id in overrides:
            selection[voice_id] = overrides[voice_id]
            continue
        takes = sorted(candidates.get(voice_id, []), key=lambda e: (e["flag"], e["cer"], e["file"]))
        if not takes:
            raise SystemExit("No checked take for " + voice_id)
        selection[voice_id] = takes[0]["file"]
        if takes[0]["flag"]:
            flagged.append(voice_id)
    write_json(WORK / "selection.json", selection)
    print(json.dumps({"lines": len(selection), "overrides": len(overrides), "still_flagged": flagged}))


# ---------------------------------------------------------------- finalize

def _loudness(src, pre_filter):
    """First loudnorm pass: measure the trimmed clip so the second pass can apply one linear gain."""
    proc = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", str(src), "-af",
                           pre_filter + ",loudnorm=I=-18:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                          capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)
    return json.loads(proc.stderr[proc.stderr.rindex("{"):proc.stderr.rindex("}") + 1])


def finalize(args):
    base = load_json(SRC / "lines_base.json")["lines"]
    translation = load_json(SRC / "translation_ja.json")
    cast = load_json(SRC / "voice_cast_ja.json")
    selection = load_json(WORK / "selection.json")  # voice_id -> chosen raw wav path
    OUT.mkdir(parents=True, exist_ok=True)
    records, by_text_key = [], {}
    for line in base:
        src = pathlib.Path(selection[line["voice_id"]])
        dst = OUT / f"{line['voice_id']}.ogg"
        profile = profile_for(cast, line["speaker_key"])
        pre, post = profile.get("pre_ms", 60) / 1000.0, profile.get("post_ms", 220) / 1000.0
        # Keep only the profile's breath margin of silence before and after the speech.
        trim = (f"silenceremove=start_periods=1:start_threshold=-45dB:start_silence={pre},"
                f"areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence={post},areverse")
        m = _loudness(src, trim)
        level = (f"loudnorm=I=-18:TP=-1.5:LRA=11:linear=true:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
                 f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}")
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(src), "-af", trim + "," + level,
                        "-ar", "24000", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", str(dst)], check=True)
        res_path = "res://assets/audio/voice/ja/" + dst.name
        records.append({"voice_id": line["voice_id"], "speaker_key": line["speaker_key"], "voice": profile["voice"],
                        "text_keys": line["text_keys"], "ko": line["ko"], "ja": translation_for(translation, line)["ja"],
                        "runtime_path": res_path, "source_take": src.parent.name, "source_sha256": sha256(src),
                        "runtime_sha256": sha256(dst)})
        for text_key in line["text_keys"]:
            by_text_key[text_key] = res_path
    provenance = {"service": "Alibaba Cloud Model Studio Token Plan (Singapore, ap-southeast-1)", "model": MODEL,
                  "authorized_by": "user request 2026-09-27",
                  "note": "Pre-rendered files; the game performs no runtime or online TTS."}
    # Runtime manifest stays small (it ships in the PCK); the full per-line record is the committed source of truth.
    write_json(OUT / "voice_manifest.json", {"schema_version": 1, "language": "ja", "provenance": provenance,
                                             "by_text_key": dict(sorted(by_text_key.items()))})
    write_json(SRC / "voice_lines_ja.json", {"schema_version": 1, "generated_by": "tools/voice/voice_ja_pipeline.py finalize",
                                             "provenance": provenance, "lines": records})
    print(json.dumps({"files": len(records), "text_keys": len(by_text_key)}))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="step", required=True)
    sub.add_parser("extract").set_defaults(fn=extract)
    j = sub.add_parser("jobs")
    j.add_argument("--take", type=int, default=1)
    j.add_argument("--ids")
    j.set_defaults(fn=jobs)
    r = sub.add_parser("run")
    r.add_argument("jobs")
    r.add_argument("--workers", type=int, default=4)
    r.set_defaults(fn=run)
    q = sub.add_parser("qa")
    q.add_argument("jobs")
    q.add_argument("--out", default=str(WORK / "qa.json"))
    q.add_argument("--model", default="medium")
    q.add_argument("--threshold", type=float, default=0.2)
    q.add_argument("--force", action="store_true")
    q.add_argument("--recheck", action="store_true", help="add the styled second pass to already-checked flagged takes")
    q.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    q.add_argument("--dll-dir")
    q.set_defaults(fn=qa)
    rs = sub.add_parser("rescore")
    rs.add_argument("report")
    rs.add_argument("--threshold", type=float, default=0.2)
    rs.set_defaults(fn=rescore)
    s = sub.add_parser("select")
    s.add_argument("reports", nargs="+")
    s.add_argument("--overrides", default=str(WORK / "selection_overrides.json"))
    s.set_defaults(fn=select)
    sub.add_parser("finalize").set_defaults(fn=finalize)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
