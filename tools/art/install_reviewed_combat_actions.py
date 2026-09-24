"""Install the explicitly reviewed September 13 SD action candidate for runtime QA."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
B=ROOT/'work/combat_motion_20260913'
P=B/'packed_candidate'
DEST=ROOT/'godot/assets/runtime_web/action_frames/r1'
NOTES={
 'CHR001':'Lantern swing, planted shield thrust and heavy overhead lantern bash. Shield, chain and teal identity retained.',
 'CHR002':'r3 basic/ultimate release corrected from overhead anticipation to completed downward cleave. Normal rising slash from r2. Full blade and ribbons retained.',
 'CHR003':'Shoulder aim/recoil, kneeling precision shot, wide braced charged shot. Rifle grip and silver-blue silhouette retained. Kneeling skill settles crouched before idle recovery.',
 'CHR004':'Short energy shot, low burst, lunging charged discharge. Real knee/arm/weapon poses with stable purple identity.',
 'CHR005':'Heavy cannon brace/recoil, elevated mortar shot, wide charged shot. Emerald chamber is intentional solid material; canonical extractor chroma-adjacent threshold 450 applies only to this actor (observed maximum 399). No keyed chamber hole or edge spill in reviewed export.',
 'CHR006':'Focus draw, arm sweep and elevated two-arm cast. Sapphire focus, braid and coat identity retained.',
 'CHR007':'Staff thrust, tome reading cast and overhead staff sweep. Tome and astrolabe remain held; no missing tips.',
 'CHR008':'Staff thrust, gentle healing extension and open protective gesture. Medical shield, staff and lavender braid retained.',
 'ENM001':'Crouch/pounce/land and raised foreclaw slash; real forelimb articulation, left facing.',
 'ENM002':'Cannon aim/recoil and fin-braced heavy shot; articulated barrel and fins, left facing.',
 'ENM003':'Folded-fin shield ram and six-fin defensive pulse; intact teal shell and fins.',
 'BOSS001':'Braced cannon recoil and shield lift/heavy cannon thrust; intact cathedral silhouette, joints and weapon.'
}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 index=json.loads((P/'index.json').read_text());assert set(index['actors'])==set(NOTES)
 report={'status':'SOURCE_POSE_VISUAL_REVIEW_PASS_RUNTIME_QA_PENDING','review':'All 192 poses reviewed in ordered six-pose full-resolution sheets against approved SD identity. Non-loop start/windup/release/follow-through/recovery assessed. Actual renderer and live battle validation remain separate.','actors':{},'rejected':['initial six-subject strips: touching weapons and clipped components, not promoted','CHR002 r2 basic/ultimate release: overhead anticipation repeated at strike; replaced by r3'], 'provider':'Sprite Gen canonical GPT Codex route, previously explicitly authorized'}
 for id,note in NOTES.items():
  item=index['actors'][id];folder=P/id
  assert digest(folder/'atlas.png')==item['atlas_sha256']
  assert digest(folder/'manifest.json')==item['manifest_sha256']
  manifest=json.loads((folder/'manifest.json').read_text())
  assert all(len(s)==6 for s in manifest['states'].values())
  revision='r3' if id=='CHR002' else 'r2'
  raw=B/revision/id/'raw'
  report['actors'][id]={'note':note,'frames':sum(map(len,manifest['states'].values())),'actions':list(manifest['states']),'hashes':item,'source_rows':{str(p.relative_to(ROOT)):digest(p) for p in sorted(raw.glob('*.png'))}}
  (B/revision/id/'qa-notes.md').write_text('# SD non-loop attack pose review\n\n'+note+'\n\nOrdered pose review: PASS. Runtime timing and motion capture are validated separately under reports/combat_motion_20260913.\n',encoding='utf8')
  target=DEST/id;target.mkdir(parents=True,exist_ok=True)
  for file in ['atlas.png','manifest.json']:shutil.copy2(folder/file,target/file)
 index['status']='VISUAL_MOTION_REVIEW_PASS'
 (P/'index.json').write_text(json.dumps(index,indent=2))
 (DEST/'index.json').write_text(json.dumps(index,indent=2))
 out=ROOT/'reports/combat_motion_20260913';out.mkdir(exist_ok=True)
 (out/'source_review.json').write_text(json.dumps(report,indent=2),encoding='utf8')
 print('INSTALLED',len(NOTES),'actors',sum(x['frames'] for x in report['actors'].values()),'poses; live player unchanged')
if __name__=='__main__':main()
