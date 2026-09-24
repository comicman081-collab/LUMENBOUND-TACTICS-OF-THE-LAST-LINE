"""Prepare/run canonical Sprite Gen action rows; candidates require visual approval."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, subprocess
from PIL import Image, ImageDraw
from prepare_existing_roster_spritegen import FINGERPRINTS

ROOT = Path(__file__).resolve().parents[2]
BATCH = ROOT / 'work/combat_motion_20260913'
SG = Path('C:/Users/AAA/.codex/skills/sprite-gen/.venv/Scripts/python.exe')
ACTIONS = {
 'CHR001': ['plant rear foot and pull lantern mace back, shield protects torso; swing the chained lantern forward at chest height; recover into guarded ready stance', 'crouch behind shield, rotate shoulders, thrust kite shield forward with planted front leg, recoil and reset', 'lower hips behind shield, raise lantern overhead, drive shield and lantern forward in a commanding heavy bash, recover guard'],
 'CHR002': ['two-handed sword windup over rear shoulder; diagonal descending greatsword cut, follow-through across front leg, then recover ready guard', 'lower greatsword near rear hip, low advancing stance, rising two-handed greatsword cut, sword high follow-through, recover', 'deep planted stance, greatsword lifted overhead with both hands, powerful overhead cleave with bent front knee, low follow-through then recover'],
 'CHR003': ['bring rifle stock tight to shoulder, align eye to scope, fire forward, shoulder recoil with muzzle slight rise, settle aim, return ready', 'kneel on rear knee, keep both hands on rifle, precision aimed shot forward, controlled recoil and return to crouched ready', 'wide planted stance, lean into scoped rifle, powerful charged shot with strong shoulder recoil and ponytail follow-through, settle and recover'],
 'CHR004': ['raise compact energy gun in both hands, sight forward, short shot and wrist/shoulder recoil, settle barrel, recover ready', 'lower into forward braced stance, fire a sustained burst with small distinct successive recoil poses, settle back', 'turn shoulders into low lunging firing stance, brace energy firearm with both hands, powerful forward discharge, strong recoil and controlled recovery'],
 'CHR005': ['brace heavy cannon in both hands, bend knees, aim cannon forward, recoil pulls shoulders backward while feet stay grounded, settle barrel, recover', 'set rear foot and crouch, elevate cannon diagonally upward for mortar shot, cannon kicks down and back, settle and return', 'deep wide firing stance, heavy cannon charged and aimed horizontally, massive shot with pronounced recoil through shoulders and knees, controlled follow-through and recovery'],
 'CHR006': ['draw casting hand toward chest while sapphire focus stays beside hand, extend hand forward in a precise casting thrust, retract and recover', 'lower stance and sweep casting arm across torso, lift sapphire focus at hand, send energy forward with open palm, settle', 'raise both arms with sapphire focus above leading hand, arch coat and hair with full body casting gesture, thrust leading palm forward and lower arms'],
 'CHR007': ['hold tome in supporting hand, draw staff back, point astrolabe staff forward, torso follows then returns to ready', 'open tome toward face and angle staff diagonally up, read and extend staff forward, close gesture and recover', 'raise astrolabe staff high while holding open tome, kneel slightly, sweep staff forward in a large arc, plant it and recover'],
 'CHR008': ['raise short crystal staff while keeping round medical shield close, point staff forward, lower arm and return ready', 'crouch slightly behind medical shield, extend staff gently upward and outward to heal ally, settle arms', 'lift medical shield and crystal staff together, open both arms in a strong protective healing gesture, bring shield back and settle'],
 'ENM001': ['lower front legs, pull predatory head back, pounce with foreclaws extended toward LEFT, land forefeet, recover crouch', 'coil low, raise one blade foreclaw, slash forward with jaw extended, land and reset'],
 'ENM002': ['tilt hovering gun drone back, align long cannon LEFT, recoil backward on firing, stabilize fins, recover hover', 'fold stabilizer fins into braced angle, raise cannon slightly then thrust forward, heavy backward recoil, recover stable hover'],
 'ENM003': ['tilt shield shell toward LEFT, pull fins back, ram shell forward, recoil and recover hover', 'spread six fins, brace shield face toward LEFT, pulse forward through whole shell, settle fins'],
 'BOSS001': ['plant colossal legs, rotate cannon arm toward LEFT, brace behind circular shield, fire with heavy articulated recoil, recover', 'bend heavy knees, lift huge shield and cannon, bring shield down and thrust cannon LEFT, massive shoulder recoil, settle towering stance'],
}

def execute(args, log):
    tmp=BATCH/'tmp'; tmp.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy(); env.update(TEMP=str(tmp),TMP=str(tmp),PYTHONDONTWRITEBYTECODE='1',SPRITE_GEN_GEN_TIMEOUT_SECONDS='480')
    with log.open('w',encoding='utf8') as f:
        p=subprocess.run([str(SG),'-B','-m','sprite_gen.cli',*args],cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
    return p.returncode

def prepare(ids):
    BATCH.mkdir(parents=True,exist_ok=True); (BATCH/'logs').mkdir(exist_ok=True)
    board=Image.new('RGB',(1200,400*((len(ids)+3)//4)), '#12232f'); draw=ImageDraw.Draw(board)
    records=[]
    for n,entity in enumerate(ids):
        source=ROOT/f'data_source/art_source/roster_replacements_20260911/{entity}/source.png'
        image=Image.open(source).convert('RGBA'); image.thumbnail((280,350))
        x=(n%4)*300+(300-image.width)//2;y=(n//4)*400+30
        board.paste(image,(x,y),image);draw.text(((n%4)*300+12,(n//4)*400+8),entity,fill='white')
        run=BATCH/entity
        states={}
        for i,action in enumerate(ACTIONS[entity]):
            state=['basic_attack','normal_skill','ultimate'][i]
            for phase,poses in [('prepare','ready guard, anticipation with body lowering and arms retracting, full windup immediately BEFORE release'),('release','full strike or muzzle release, follow-through or recoil, recovered ready guard')]:
                states[state+'_'+phase]={'frames':3,'fps':8,'loop':False,'action':action+'. This strip contains ONLY these THREE chronological poses: '+poses+'. Preserve camera angle and anatomy; change real arm, leg and weapon articulation, never merely rotate an unchanged drawing. SAME head size and anatomical scale throughout. Keep every complete body and weapon within the central 60 percent of its slot width. Generous empty green gaps between poses are mandatory. No detached effects. Weapon remains held correctly.'}
                if entity=='CHR002' and phase=='release' and state in ['basic_attack','ultimate'] and BATCH.name=='r3':
                    states[state+'_'+phase]['action']='THREE POSES ONLY, of the END of a downward greatsword cleave. FIRST: sword blade ALREADY DOWN and EXTENDED to the lower RIGHT in front of bent forward knee at the instant of impact; hands forward near waist. SECOND: sword stays LOW to the right in completed follow-through, shoulders forward. THIRD: return to the exact reference ready guard. NO overhead sword pose, no winding up, no raising sword in this strip. Both hands remain on the hilt. Same face, costume, size and facing RIGHT as reference. Separate the three figures with wide GREEN gutters; keep every full blade tip and ribbon complete.'
        request={'states':states,'cell':{'width':512,'height':512,'safe_margin':72},'fit':{'resample':'lanczos','align_x':'bbox-center','align_y':'bottom','ground_frames':True,'pixel_unfake':False},'style':'Match the attached approved SD combat artwork exactly: same adult face, costume, anatomy proportions, 3/4 camera, palette, weapon, refined painted anime linework. NOT pixel art. Do not change costume or restyle. Full subject and weapon visible in every pose. Flat uniform #00FF00 chroma green, no shadows, green spill, text, background scenery, effects or grids.'}
        recipe=BATCH/f'{entity}.request.json';recipe.write_text(json.dumps(request,indent=2),encoding='utf8')
        if not (run/'sprite-request.json').exists():
            code=execute(['prepare','--out-dir',str(run),'--character-id',entity,'--base-image',str(source),'--description',FINGERPRINTS[entity]+' Facing '+('RIGHT' if entity.startswith('CHR') else 'LEFT')+'. Identity and costume are immutable.','--chroma-key','#00FF00','--request',str(recipe)],BATCH/'logs'/f'{entity}_prepare.log')
            if code: raise RuntimeError(f'{entity} prepare failed: see log')
        records.append({'id':entity,'source':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'states':list(states)})
    board.save(BATCH/'approved_references.jpg')
    (BATCH/'inventory.json').write_text(json.dumps({'status':'CANDIDATES_NOT_PROMOTED','provider':'codex','route':'Sprite Gen GPT image rows; previous explicit GPT and Sprite Gen authorization persists','entities':records},indent=2),encoding='utf8')

def main():
    global BATCH
    p=argparse.ArgumentParser();p.add_argument('step',choices=['prepare','generate','extract','compose','export']);p.add_argument('--ids',default=','.join(ACTIONS));p.add_argument('--concurrency',type=int,default=3);p.add_argument('--revision',default='r2');args=p.parse_args();ids=args.ids.split(',')
    assert args.revision in ['r2','r3']
    BATCH=BATCH/args.revision
    assert set(ids)<=set(ACTIONS)
    if args.step=='prepare':prepare(ids);return
    def run(entity):
        directory=BATCH/entity
        commands={'generate':[['gen-set','--provider','codex','--concurrency','2']], 'extract':[['extract']], 'compose':[['compose-atlas'],['compose-gif'],['preview'],['inspect']], 'export':[['export-pngs']]}
        for command in commands[args.step]:
            code=execute(command+['--run-dir',str(directory)],BATCH/'logs'/f'{entity}_{command[0]}.log')
            if code:return {'id':entity,'step':command[0],'exit':code}
        return {'id':entity,'step':args.step,'exit':0}
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        for result in pool.map(run,ids):
            results.append(result);print(json.dumps(result),flush=True)
            (BATCH/f'{args.step}_status.json').write_text(json.dumps(results,indent=2),encoding='utf8')
    if any(r['exit'] for r in results):raise SystemExit(1)

if __name__=='__main__':main()
