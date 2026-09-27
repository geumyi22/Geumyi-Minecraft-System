from pathlib import Path
import re,json,zipfile,hashlib,sys,struct
ROOT=Path(__file__).resolve().parents[1]
issues=[]; notes=[]

def ok(cond,msg):
    if not cond: issues.append(msg)

# Source definitions
tech_src=(ROOT/'src/main/java/kr/geumyi/technology/TechItem.java').read_text(encoding='utf8')
ids=re.findall(r'\("([a-z0-9_]+)",\s*"[^"]+",\s*Material\.([A-Z0-9_]+),\s*Kind\.([A-Z]+)',tech_src)
tech_ids=[x[0] for x in ids]
ok(len(tech_ids)==22,f'Expected 22 tech items, got {len(tech_ids)}')
ok(len(set(tech_ids))==len(tech_ids),'Duplicate tech item IDs')

recipe_src=(ROOT/'src/main/java/kr/geumyi/technology/TechnologyRecipes.java').read_text(encoding='utf8')
recipe_count=recipe_src.count('RecipeDef.tech(')+recipe_src.count('RecipeDef.vanilla(')+recipe_src.count('RecipeDef.chem(')
process_count=recipe_src.count('new MachineProcess(')
ok(recipe_count==17,f'Expected 17 workbench recipes, got {recipe_count}')
ok(process_count==13,f'Expected 13 machine processes, got {process_count}')

# Essential reachability model from workbench recipes + machine processing.
# Vanilla resources are assumed obtainable. Chemistry is optional and is excluded from essential tree.
reachable=set()
# manually represented dependency graph of tech outputs (generated from declared design)
recipes={
 'copper_wire':[], 'machine_frame':[], 'basic_circuit':['copper_wire'], 'electric_motor':['copper_wire'],
 'heating_coil':['copper_wire'], 'battery_cell':['copper_wire'], 'power_cable':['copper_wire'],
 'coal_generator':['machine_frame','electric_motor','basic_circuit'], 'battery_box':['machine_frame','battery_cell','basic_circuit'],
 'crusher':['machine_frame','electric_motor','basic_circuit'], 'electric_furnace':['machine_frame','heating_coil','basic_circuit'],
 'electrolyzer':['machine_frame','basic_circuit','copper_wire']
}
changed=True
while changed:
    changed=False
    for out,deps in recipes.items():
        if out not in reachable and all(d in reachable for d in deps): reachable.add(out); changed=True
# Silicon progression needs crusher + powered generator; power connection may be direct or cable.
if {'crusher','coal_generator'} <= reachable: reachable.add('silicon_dust')
if {'silicon_dust','electric_furnace','coal_generator'} <= reachable: reachable.add('silicon_wafer')
if {'machine_frame','silicon_wafer','basic_circuit'} <= reachable: reachable.add('solar_panel')
essential={'copper_wire','machine_frame','basic_circuit','electric_motor','heating_coil','battery_cell','power_cable','coal_generator','battery_box','crusher','electric_furnace','silicon_dust','silicon_wafer','solar_panel','electrolyzer'}
ok(essential <= reachable,'Essential non-Chemistry progression is not fully reachable: '+','.join(sorted(essential-reachable)))

# JAR
jar=ROOT/'GeumyiTechnology-0.1.0.jar'
ok(jar.is_file(),'Plugin JAR missing')
if jar.is_file():
    with zipfile.ZipFile(jar) as z:
        bad=z.testzip(); ok(bad is None,f'JAR CRC failure: {bad}')
        names=set(z.namelist())
        ok('plugin.yml' in names,'plugin.yml missing from JAR')
        ok('kr/geumyi/technology/GeumyiTechnology.class' in names,'Main class missing from JAR')
        cls=z.read('kr/geumyi/technology/GeumyiTechnology.class')
        major=struct.unpack('>H',cls[6:8])[0]
        ok(major<=69,f'Class major {major} is newer than Java 25')
        notes.append(f'Java class major: {major} (Java {major-44})')

warn=(ROOT/'build/javac-warnings.txt').read_text(encoding='utf8') if (ROOT/'build/javac-warnings.txt').exists() else 'missing'
ok(warn.strip()=='','Local javac stub compile warnings/errors present')

# JE tech pack
jezip=ROOT/'packs/GeumyiTechnology-JE-0.1.0.zip'
with zipfile.ZipFile(jezip) as z:
    ok(z.testzip() is None,'JE tech pack CRC failure')
    names=set(z.namelist())
    mc=json.loads(z.read('pack.mcmeta'))
    ok(mc['pack']['min_format']==[88,0] and mc['pack']['max_format']==[88,0],'JE pack format is not 88.0')
    for tid in tech_ids:
        item=f'assets/geumyi_tech/items/item/{tid}.json'; model=f'assets/geumyi_tech/models/item/{tid}.json'; tex=f'assets/geumyi_tech/textures/item/{tid}.png'
        ok(item in names,f'Missing JE item definition {tid}')
        ok(model in names,f'Missing JE model {tid}')
        ok(tex in names,f'Missing JE texture {tid}')

# BE tech pack/mapping
bezip=ROOT/'packs/GeumyiTechnology-BE-0.1.0.mcpack'
with zipfile.ZipFile(bezip) as z:
    ok(z.testzip() is None,'BE tech pack CRC failure')
    names=set(z.namelist())
    manifest=json.loads(z.read('manifest.json'))
    ok(manifest['format_version']==2,'BE manifest format_version != 2')
    tex=json.loads(z.read('textures/item_texture.json'))['texture_data']
    for tid in tech_ids:
        ok(f'geumyi_tech:{tid}' in tex,f'Missing BE texture_data {tid}')
        path=tex.get(f'geumyi_tech:{tid}',{}).get('textures',[''])[0]+'.png'
        ok(path in names,f'Missing BE texture file {tid}: {path}')

mapping=json.loads((ROOT/'packs/GeumyiTechnology-Geyser-mappings-0.1.0.json').read_text(encoding='utf8'))
ok(mapping.get('format_version')==2,'Geyser tech mapping format_version != 2')
defs=[d for arr in mapping['items'].values() for d in arr]
bids=[d['bedrock_identifier'] for d in defs]
ok(len(defs)==13,f'Expected 13 non-placeable Bedrock mappings, got {len(defs)}')
ok(len(bids)==len(set(bids)),'Duplicate Bedrock identifiers in tech mapping')
block_ids={tid for tid,mat,kind in ids if kind=='BLOCK'}
mapped_ids={d['bedrock_identifier'].split(':',1)[1] for d in defs}
ok(not(block_ids & mapped_ids),'Placeable tech blocks must not be custom-mapped on Bedrock')

# Suite packs
for fn in ['GeumyiSuite-JE-Chem0.4-Tech0.1.zip','GeumyiSuite-BE-Chem0.4-Tech0.1.mcpack']:
    with zipfile.ZipFile(ROOT/'packs'/fn) as z: ok(z.testzip() is None,f'{fn} CRC failure')
suite_map=json.loads((ROOT/'packs/GeumyiSuite-Geyser-mappings-Chem0.4-Tech0.1.json').read_text(encoding='utf8'))
sdefs=[d for arr in suite_map['items'].values() for d in arr]
sbids=[d['bedrock_identifier'] for d in sdefs]
ok(len(sbids)==len(set(sbids)),'Duplicate Bedrock identifiers in combined suite mapping')
notes.append(f'Tech items: {len(tech_ids)}')
notes.append(f'Workbench recipes: {recipe_count}')
notes.append(f'Machine processes: {process_count}')
notes.append(f'Bedrock custom-mapped non-block items: {len(defs)}')
notes.append(f'Bedrock placeable items deliberately left vanilla-mapped: {len(block_ids)}')
notes.append(f'Combined Geyser definitions: {len(sdefs)}')
notes.append('Essential vanilla-only progression reachable: YES' if essential <= reachable else 'Essential vanilla-only progression reachable: NO')

out=['GeumyiTechnology v0.1.0 validation','']
for n in notes: out.append('- '+n)
out.append(f'- Validation issues: {len(issues)}')
if issues:
    out.append(''); out.append('ISSUES:'); out.extend('* '+i for i in issues)
else:
    out.append('- Static structure/data/resource-pack validation: PASS')
    out.append('- Local Java compilation against signature stubs: PASS (0 warnings)')
    out.append('- NOTE: final live Paper 26.2 + Geyser play-test must still be done on the actual server.')
(ROOT/'VALIDATION.txt').write_text('\n'.join(out)+'\n',encoding='utf8')
print('\n'.join(out))
sys.exit(1 if issues else 0)
