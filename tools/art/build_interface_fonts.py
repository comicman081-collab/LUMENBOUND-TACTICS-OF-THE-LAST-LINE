"""Build deterministic OFL static faces; original font remains untouched."""
from pathlib import Path
import hashlib, json
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / 'godot/assets/fonts'
SOURCE = FONTS / 'NotoSansKR-VF.ttf'
records = []
for style, weight in [('Medium', 500), ('SemiBold', 650), ('Black', 900)]:
    font = instantiateVariableFont(TTFont(SOURCE), {'wght': weight}, inplace=True)
    for name_id, value in {1:'Lantern Sans', 2:style, 4:f'Lantern Sans {style}', 6:f'LanternSans-{style}', 16:'Lantern Sans', 17:style}.items():
        for platform, encoding, language in [(3,1,0x409), (1,0,0)]:
            font['name'].setName(value,name_id,platform,encoding,language)
    path = FONTS / f'LanternSans-{style}.ttf'
    font.save(path)
    records.append({'path':str(path.relative_to(ROOT)), 'weight':weight, 'glyphs':len(font.getBestCmap()), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    print('BUILT',path,flush=True)
(FONTS/'LanternSans-manifest.json').write_text(json.dumps({'source':str(SOURCE.relative_to(ROOT)), 'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'license':'SIL OFL 1.1', 'license_file':'NotoSansKR-OFL.txt','modification':'Static weights; renamed Lantern Sans; full original character coverage retained', 'faces':records},indent=2),encoding='utf-8')
