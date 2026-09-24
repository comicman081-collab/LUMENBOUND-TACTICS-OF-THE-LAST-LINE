"""Project-contained batch driver for the installed canonical Sprite Gen CLI.

Does not implement a provider, matte, cropper or animation pipeline itself.
Generated candidates require a separate visual review before promotion.
"""
from pathlib import Path
import argparse
import concurrent.futures
import json
import os
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / 'work/enemy_replacement_20260911'
PYTHON = Path('C:/Users/AAA/.codex/skills/sprite-gen/.venv/Scripts/python.exe')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', default='all')
    parser.add_argument('--concurrency', type=int, default=6)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--run-name', default='enemy_replacement_20260911')
    args = parser.parse_args()
    run=(ROOT/'work'/args.run_name).resolve()
    assert run.is_relative_to((ROOT/'work').resolve())
    refs={}
    if args.inventory:
        inventory=json.loads(args.inventory.read_text(encoding='utf8'))
        refs={row['entity_id']:[ROOT/row['reference']] for row in inventory['assets']}
        known=set(refs)
    else:
        audit = json.loads((ROOT/'reports/enemy_replacement_20260911/missing_monster_audit.json').read_text(encoding='utf8'))
        known = {row['id'] for row in audit['entities']}
    wanted = sorted(known if args.ids == 'all' else set(args.ids.split(',')))
    assert set(wanted).issubset(known) and 1 <= args.concurrency <= 6
    out = run/'gpt_candidates'
    out.mkdir(exist_ok=True)
    logs = run/'spritegen_logs'
    logs.mkdir(exist_ok=True)
    env = os.environ.copy()
    (run/'tmp').mkdir(exist_ok=True)
    env.update(TEMP=str(run/'tmp'), TMP=str(run/'tmp'), PYTHONDONTWRITEBYTECODE='1', SPRITE_GEN_GEN_TIMEOUT_SECONDS='360')
    authorization = {'provider':'codex', 'backend':'Codex built-in GPT image generation through Sprite Gen 2.1.0', 'authorization':'User explicitly authorized GPT imagegen for this monster batch in the current conversation.', 'raw_master':'Uniform chroma green; preserve alongside separate RGBA derivative', 'promotion':'Separate visual and runtime checks required', 'local_models':'No local model or original runtime artifact is modified.'}
    (run/'spritegen_authorization.json').write_text(json.dumps(authorization,ensure_ascii=False,indent=2),encoding='utf8')

    def generate(entity):
        image = out/f'{entity}.png'
        report = out/f'{entity}.report.json'
        if image.exists() and report.exists():
            record=json.loads(report.read_text(encoding='utf8'))
            if record.get('provider') == 'codex' and record.get('alpha',{}).get('alpha_zero_pct',0)>0:
                return {'entity':entity,'status':'EXISTING_CANDIDATE_REVIEW_REQUIRED'}
        if image.exists() or report.exists():
            return {'entity':entity,'status':'FAIL_PARTIAL_OUTPUT_RETAINED'}
        args=[str(PYTHON),'-B','-m','sprite_gen.cli','gen','--provider','codex','--prompt-file',str(run/'prompts'/f'{entity}.txt'),'--out',str(image),'--transparent','--alpha-mode','chroma','--chroma-key','green','--report',str(report),'--keep-session']
        for reference in refs.get(entity,[]):args.extend(['--ref',str(reference)])
        started=time.monotonic()
        with (logs/f'{entity}.log').open('w',encoding='utf8') as log:
            process=subprocess.run(args,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        return {'entity':entity,'status':'CANDIDATE_REVIEW_REQUIRED' if process.returncode==0 else 'FAIL_GENERATION_RETAINED','exit_code':process.returncode,'seconds':round(time.monotonic()-started,2)}

    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        pending={pool.submit(generate,entity):entity for entity in wanted}
        for future in concurrent.futures.as_completed(pending):
            try: result=future.result()
            except Exception as exc: result={'entity':pending[future],'status':'FAIL_DRIVER','error':str(exc)}
            results.append(result)
            (run/'spritegen_batch_status.json').write_text(json.dumps({'status':'CANDIDATES_NOT_PROMOTED','completed':len(results),'requested':len(wanted),'results':results},ensure_ascii=False,indent=2),encoding='utf8')
            print(json.dumps(result),flush=True)
    if any(r['status'].startswith('FAIL') for r in results):raise SystemExit(1)


if __name__=='__main__':main()
