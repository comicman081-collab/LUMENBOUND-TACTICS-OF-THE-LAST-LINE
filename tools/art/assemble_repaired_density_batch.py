"""Stage reviewed hole repairs, preserve failed copies, rebuild all runtime paths."""
from pathlib import Path
import copy
import shutil
from build_full_density_runtime import ROOT,GODOT,read,sha,save_json,build_actor,legacy,packing

repairs={'CHR002':ROOT/'work/enclosed_matte_repair/r1/CHR002','CHR004':ROOT/'work/enclosed_matte_repair/r2/CHR004'}
runtime=GODOT/'assets/runtime_web'
qa=ROOT/'work/full_density/r2'
quarantine=ROOT/'work/gameplay_qa_quarantine_20260907/enclosed_white_matte'
if qa.exists() or quarantine.exists(): raise ValueError('IMMUTABLE_ASSEMBLY_EXISTS')
qa.mkdir(parents=True)
quarantine.mkdir(parents=True)
retained=[]
legacy.COMBAT_OUTPUT=qa/'compact_replacements'
for entity,repaired in repairs.items():
    source_manifest=read(repaired/'animation_manifest.json')
    before=runtime/'combat'/entity
    # Retain exact runtime inputs before any pointer is replaced. No deletion.
    shutil.copytree(before,quarantine/'compact'/entity)
    for file in sorted(before.rglob('*')):
        if file.is_file(): retained.append({'path':file.relative_to(ROOT).as_posix(),'sha256':sha(file)})
    authority=GODOT/'assets/generated_import/enclosed_matte_repair/r1'/entity
    shutil.copytree(repaired,authority)
    legacy.build_combat_pack(entity,authority)
    # Source identity and timing remain the original manifest's authority;
    # only the derived root, alpha and fully framed DOWN motion are changed.
    for file in (legacy.COMBAT_OUTPUT/entity).iterdir():
        if file.is_file(): shutil.copy2(file,before/file.name)
    build_actor(entity,runtime/'full_density/r2'/entity,qa)
save_json(quarantine/'retained_paths_and_hashes.json',{'reason':'USER_REPORTED_ENCLOSED_WHITE_MATTE_FAIL','disposal':'PROHIBITED_PENDING_ALL_GATES','assets':retained})

old_index=read(runtime/'full_density/r1/index.json')
new_index=copy.deepcopy(old_index)
new_index['revision']='r2'
for entity in old_index['actors']:
    destination=runtime/'full_density/r2'/entity
    if entity not in repairs: shutil.copytree(runtime/'full_density/r1'/entity,destination)
    manifest=read(destination/'animation_manifest.json')
    new_index['actors'][entity].update(manifest_sha256=sha(destination/'animation_manifest.json'),decoded_rgba_bytes=manifest['decoded_rgba_bytes'],source=manifest['source_root'])
save_json(runtime/'full_density/r2/index.json',new_index)

signature_destination=runtime/'combat_signature/r14'
signature_destination.mkdir(parents=True,exist_ok=False)
approval=read(runtime/'combat_signature/r13/promotion_approval.json')
approval['signature_revision']='r14'
approval['approval_scope']+='; CHR002/CHR004 enclosed white matte repaired in all frames'
all_manifests=[]
for entity in approval['manifest_sha256_by_character']:
    if entity not in repairs:
        shutil.copytree(runtime/'combat_signature/r13'/entity,signature_destination/entity)
    else:
        source={**packing.SOURCES[entity], 'root':GODOT/'assets/generated_import/enclosed_matte_repair/r1'/entity}
        source['manifest']=source['root']/'animation_manifest.json'
        source['authority_status']='LOCAL_QA_ONLY_ENCLOSED_MATTE_REPAIR'
        source['chroma_key_provenance']={'repair_manifest':(source['root']/'repair_manifest.json').relative_to(ROOT).as_posix(),'green_master_sha256':sha(source['root']/'green_master.png'),'mask_sha256':sha(source['root']/'approved_region_mask.png'),'no_costume_change':True}
        packing.build_entity(entity,'r14',signature_destination,source)
    file=signature_destination/entity/'signature_manifest.json'
    approval['manifest_sha256_by_character'][entity]=sha(file)
    all_manifests.append(read(file))
core=sum(a['atlas_size'][0]*a['atlas_size'][1]*4 for m in all_manifests for name,a in m['animations'].items() if name!='ultimate')
ult={m['character_id']:m['animations']['ultimate']['atlas_size'][0]*m['animations']['ultimate']['atlas_size'][1]*4 for m in all_manifests}
gate=approval['technical_gate']
gate.update(estimated_core_resident_atlas_bytes_for_all_selected=core,ultimate_atlas_bytes_by_character=ult,estimated_peak_transient_resident_atlas_bytes=core+max(ult.values()),estimated_full_preload_atlas_bytes_for_all_selected=core+sum(ult.values()),estimated_resident_atlas_bytes_for_all_selected=core+sum(ult.values()))
if core+max(ult.values())>72*1024*1024: raise ValueError('SIGNATURE_MEMORY_FAIL_RETAIN_CANDIDATE')
save_json(signature_destination/'promotion_approval.json',approval)
save_json(qa/'assembly_manifest.json',{'status':'LOCAL_QA_ONLY_RUNTIME_VERIFICATION_PENDING','old_full_density_r1':'FAIL_ENCLOSED_WHITE_MATTE_NOT_RUNTIME','repaired_entities':list(repairs),'all_actor_count':len(new_index['actors']),'signature_peak_bytes':core+max(ult.values()),'no_deployment':True,'no_deletion':True})
print('REPAIRED_DENSITY_ASSEMBLY_READY_FOR_LOCAL_RUNTIME_QA')
