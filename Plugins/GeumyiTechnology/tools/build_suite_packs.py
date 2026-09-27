from pathlib import Path
import shutil, json, zipfile, uuid

ROOT=Path('/mnt/data/GeumyiTechnology-v0.1.0')
WORK=Path('/mnt/data/geumyi_technology_work')
OUT=ROOT/'packs'
CHEM_JE=WORK/'chem_je'
CHEM_BE=WORK/'chem_be'
TECH_JE=OUT/'je'
TECH_BE=OUT/'be'
SUITE_JE=OUT/'suite_je'
SUITE_BE=OUT/'suite_be'
for p in [SUITE_JE,SUITE_BE]:
    if p.exists(): shutil.rmtree(p)

shutil.copytree(CHEM_JE,SUITE_JE)
# overwrite metadata/icon and add tech assets
for src in (TECH_JE/'assets').rglob('*'):
    if src.is_file():
        dst=SUITE_JE/'assets'/src.relative_to(TECH_JE/'assets')
        dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
(SUITE_JE/'pack.mcmeta').write_text(json.dumps({'pack':{'description':'Geumyi Suite · Chemistry 0.4.0 + Technology 0.1.0 · Java 26.2','min_format':[88,0],'max_format':[88,0]}},ensure_ascii=False,indent=2),encoding='utf8')
shutil.copy2(TECH_JE/'pack.png',SUITE_JE/'pack.png')

# Merge Bedrock resources into one pack, using chemistry pack as base.
shutil.copytree(CHEM_BE,SUITE_BE)
chem_tex=json.load(open(CHEM_BE/'textures/item_texture.json',encoding='utf8'))
tech_tex=json.load(open(TECH_BE/'textures/item_texture.json',encoding='utf8'))
merged=chem_tex['texture_data'].copy()
for key,val in tech_tex['texture_data'].items():
    # copy textures under a tech_ prefix to avoid generic path collisions
    src_path=TECH_BE/(val['textures'][0]+'.png')
    dst_rel=f'textures/items/tech_{key.split(":",1)[1]}'
    dst_path=SUITE_BE/(dst_rel+'.png')
    dst_path.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src_path,dst_path)
    merged[key]={'textures':[dst_rel]}
(SUITE_BE/'textures/item_texture.json').write_text(json.dumps({'resource_pack_name':'Geumyi Suite BE','texture_name':'atlas.items','texture_data':merged},ensure_ascii=False,indent=2),encoding='utf8')
manifest={'format_version':2,'header':{'description':'Geumyi Suite · Chemistry 0.4.0 + Technology 0.1.0','name':'Geumyi Suite BE','uuid':str(uuid.uuid5(uuid.NAMESPACE_DNS,'geumyi-suite-be-header-chem040-tech010')),'version':[0,4,1],'min_engine_version':[1,20,0]},'modules':[{'description':'Geumyi Suite Bedrock resources','type':'resources','uuid':str(uuid.uuid5(uuid.NAMESPACE_DNS,'geumyi-suite-be-module-chem040-tech010')),'version':[0,4,1]}]}
(SUITE_BE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
shutil.copy2(TECH_BE/'pack_icon.png',SUITE_BE/'pack_icon.png')

# Merge mappings: multiple definitions sharing a base Java item are appended.
chem_map=json.load(open(WORK/'GeumyiChemistry-Geyser-mappings-0.4.0.json',encoding='utf8'))
tech_map=json.load(open(OUT/'GeumyiTechnology-Geyser-mappings-0.1.0.json',encoding='utf8'))
suite={'format_version':2,'items':{}}
for source in [chem_map,tech_map]:
    for base,defs in source['items'].items(): suite['items'].setdefault(base,[]).extend(defs)
(OUT/'GeumyiSuite-Geyser-mappings-Chem0.4-Tech0.1.json').write_text(json.dumps(suite,ensure_ascii=False,indent=2),encoding='utf8')

def zipdir(src,dest):
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob('*')):
            if f.is_file(): z.write(f,f.relative_to(src).as_posix())
zipdir(SUITE_JE,OUT/'GeumyiSuite-JE-Chem0.4-Tech0.1.zip')
zipdir(SUITE_BE,OUT/'GeumyiSuite-BE-Chem0.4-Tech0.1.mcpack')
print('suite JE/BE/mappings built')
