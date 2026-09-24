"""Complete per-frame matte provenance on fresh r16; retain r14 and failed r15."""
import copy
import shutil
from build_full_density_runtime import ROOT, GODOT, packing, read, sha, save_json

runtime = GODOT / 'assets/runtime_web/combat_signature'
destination = runtime / 'r16'
if destination.exists(): raise ValueError('IMMUTABLE_SIGNATURE_EXISTS')
destination.mkdir()
approval = copy.deepcopy(read(runtime/'r14/promotion_approval.json'))
approval['signature_revision'] = 'r16'
approval['technical_gate']['chroma_remaster_entities'] = ['CHR002', 'CHR004']
manifests = []
for entity in approval['manifest_sha256_by_character']:
    if entity in ['CHR002', 'CHR004']:
        source = dict(packing.SOURCES[entity])
        source['root'] = GODOT/'assets/generated_import/enclosed_matte_repair/r1'/entity
        source['manifest'] = source['root']/'animation_manifest.json'
        packing.SOURCES[entity] = source
        derivative = packing.build_chroma_key_derivative(entity, 'r16')
        packing.build_entity(entity, 'r16', destination, derivative)
    else:
        shutil.copytree(runtime/'r14'/entity, destination/entity)
    file = destination/entity/'signature_manifest.json'
    approval['manifest_sha256_by_character'][entity] = sha(file)
    manifests.append(read(file))
core = sum(a['atlas_size'][0]*a['atlas_size'][1]*4 for m in manifests for name,a in m['animations'].items() if name!='ultimate')
ultimate = {m['character_id']:m['animations']['ultimate']['atlas_size'][0]*m['animations']['ultimate']['atlas_size'][1]*4 for m in manifests}
approval['technical_gate'].update(estimated_core_resident_atlas_bytes_for_all_selected=core,ultimate_atlas_bytes_by_character=ultimate,estimated_peak_transient_resident_atlas_bytes=core+max(ultimate.values()),estimated_full_preload_atlas_bytes_for_all_selected=core+sum(ultimate.values()),estimated_resident_atlas_bytes_for_all_selected=core+sum(ultimate.values()))
assert core+max(ultimate.values()) <= 72*1024*1024
save_json(destination/'promotion_approval.json',approval)
save_json(ROOT/'work/enclosed_matte_repair/signature_r16_provenance.json',{'status':'LOCAL_QA_ONLY','prior_r14':'RETAINED_METADATA_GATE_FAIL','prior_r15':'RETAINED_THIN_HAIR_FRINGE_FAIL','per_frame_green_master_and_keyed_rgba':True,'no_deployment':True,'no_deletion':True})
print('SIGNATURE_R16_PER_FRAME_PROVENANCE_READY')
