"""Preserve each established character/monster's identity in its redraw request."""
from pathlib import Path
import json
import hashlib

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'work/existing_roster_spritegen_20260911'
FINGERPRINTS={
 'CHR001':'Maeru: long teal high ponytail with gold tiara, teal eyes, white/teal/gold armor, ornate large teal kite shield, gold chained teal lantern mace, teal cloth panels and armored boots. Guardian.',
 'CHR002':'Roan: scarlet asymmetric short hair and trailing long red ribbon, dark black and red segmented armor, huge broad red/black greatsword, pointed armor skirt panels and armored boots. Vanguard swordswoman.',
 'CHR003':'Narin: pale silver-blue high ponytail, blue eyes, white black cobalt tactical armor with split skirt panels and thigh straps, long scoped futuristic blue/black rifle held with both hands. Rifle assault.',
 'CHR004':'Eda: deep purple long high ponytail, purple eyes, black/violet light tactical armor, angular violet hip panels and thigh armor, compact magenta energy firearm held with both hands. Energy assault.',
 'CHR005':'Soren: golden blonde high ponytail, green eyes, olive black and brass heavy artillery armor, armored boots and long olive tabard panels, massive gold/black cannon with emerald energy chamber supported with both hands. Artillery.',
 'CHR006':'Vera: long pale blue-silver braided ponytail, bright blue eyes, tiny silver crown, black navy white robe with flowing white/cobalt cape panels, thigh-high boots, floating sapphire diamond focus with cyan rings above extended hand. Focus specialist.',
 'CHR007':'Toa: purple bob hair with long violet trailing strands, amber eyes, gold hair clips, black violet and gold scholarly robe with white front panel, ornate floating tome and golden circular astrolabe staff, dark boots. Support specialist.',
 'CHR008':'Iri: long silver lavender hair in side braid, gentle pink/violet eyes, white mint and rose-gold healer armor with long translucent mint coat tails, white thigh-high boots, small crystal staff and large round white medical shield. Medic.',
 'ENM001':'A fierce navy steel quadruped hound covered in orange ember crystal spikes, glowing fiery heart, blade claws and angular predatory head.',
 'ENM002':'A floating cobalt and silver armored gun drone with a vivid red circular reactor, long forward blue/red energy cannon and small stabilizer fins.',
 'ENM003':'A floating teal armored shield-relay drone, oval metal shell, central amber lens, six pointed stabilizer fins and a small blue underside thruster.',
 'ENM004':'An ivory and gold floating repair automaton, round cyan eye, capped green medicinal glass reservoir, four small white metal petal arms.',
 'ENM005':'A violet black crystal signal jammer, gold gyroscope rings and fins, bright cyan central prism and magenta orbital machinery.',
 'ENM006':'A sandy brass quadruped reconnaissance machine, long wedge snout, orange lens, fine teal sensor points, heavy articulated claws. Remove the old dust/floor marks.',
 'ENM007':'A floating navy and gold clockwork bell automaton, two blue lantern shoulder pods, curved mechanical arm blades, cyan underside reactor and long bell skirt.',
 'ENM008':'A hovering purple and black broadcast pylon, long sharp array fins, glowing violet concentric signal rings, dark tower reactor with small acid-yellow sensors.',
 'ENM009':'A massive dark steel and bronze armored tortoise robot, domed layered bastion shell, central cyan reactor, squat reinforced feet and two small side shield pods.',
 'ENM010':'A cobalt blue many-legged relay spider automaton with angular armored shell, two long aerials, powerful blade legs. Refine the crude flat face into intricate overlapping armor and menacing optical sensors, retain blue mechanical-spider identity.',
 'BOSS001':'A colossal cathedral siege automaton, rounded ivory and dark iron shell, golden reactor chest, large cannon arm, huge circular teal shield, heavy articulated legs and cathedral spires.',
 'BOSS002':'A colossal floating black-crimson cathedral bell engine with silver wing blades, red circular central reactor, suspended bells and purple arc machinery.',
 'BOSS003':'A gigantic floating gold and dark steel orbital relay sphere, acid-yellow chartreuse energy rings, two mechanical optical sensors, multiple long radial rods. Replace the crude flat toy face with intricately armored reactor lenses and a threatening complex silhouette.',
}


def main():
    inventory=json.loads((RUN/'reference_inventory.json').read_text(encoding='utf8'))
    (RUN/'prompts').mkdir(exist_ok=True)
    data=json.loads((ROOT/'godot/data/compiled/game_data.json').read_text(encoding='utf8'))
    characters={c['id']:c for c in data['characters']}
    for row in inventory['assets']:
        entity=row['entity_id'];reference=ROOT/row['reference']
        assert hashlib.sha256(reference.read_bytes()).hexdigest()==row['reference_sha256']
        if entity.startswith('CHR'):
            assert characters[entity]['age_category']=='ADULT'
            prompt=f'''Redraw the SAME established adult RPG character from the supplied reference as a premium high-resolution SD COMBAT sprite. This is a stylized ADULT fighter, approximately 3.5 to 4 heads tall. This is NOT an eight-head full illustration. Keep the entire body, weapon and all accessories in frame. Keep the character's recognizable face, hairstyle, palette placement, EXACT costume modules and coverage, weapon design, role and identity. Do not invent a costume or change equipment. Identity fingerprint: {FINGERPRINTS[entity]}
Use the same 3/4 combat view facing RIGHT and a clear ready/idle combat stance, viewed slightly from above. Detailed expressive eyes and mature face styling; not infant/toddler proportions. Crisp refined anime linework, layered materials, sharp metal edges, readable fingers and weapon grip, sophisticated painted shading matching high-end SD tactical game monsters. Preserve the reference's outfit without sexualizing the pose. One character, one view, no labels or text.'''
        else:
            prompt=f'''Redraw and upgrade the SAME original LUMENBOUND monster from the reference as a premium detailed SD tactical RPG enemy sprite. Preserve the identifying body construction, palette, silhouette, weapon role and motifs, while substantially improving linework, layered mechanical anatomy, material contrast, intricate panel construction and threatening presence. Identity: {FINGERPRINTS[entity]}
One entire nonhuman monster only, 3/4 view facing LEFT, viewed slightly from above. Detailed painted anime game art, crisp readable contour, all feet, horns, weapons, wings and tips complete. No flat polygon blob or toy face. No corpse or defeated pose. No duplicate view, no labels or text.'''
        prompt+='\nUse a perfectly uniform flat #00FF00 chroma-green background with at least 10 percent empty margin all around. No floor, cast shadow, scenery, vignette, texture, checkerboard or reflected green spill. Keep fine hair and weapon gaps separated. This green is only a removable production background; preserve the character or monster\'s intended teal/cyan/chartreuse material colors exactly.'
        (RUN/'prompts'/f'{entity}.txt').write_text(prompt,encoding='utf8')
        row['fingerprint']=FINGERPRINTS[entity]
        row['character_contract']='UNCHANGED_IDENTITY_AND_COSTUME' if entity.startswith('CHR') else 'ESTABLISHED_CREATURE_IDENTITY_UPGRADE'
    inventory['status']='READY_FOR_AUTHORIZED_GPT_REFERENCE_REDRAW'
    (RUN/'reference_inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2),encoding='utf8')


if __name__=='__main__':main()
