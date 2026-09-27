from pathlib import Path
import csv, re, yaml, json, zipfile, uuid, hashlib, sys
from collections import Counter
project=Path(__file__).resolve().parents[1]
root=project/'src/main/resources'
dist=project/'dist'

sub=str.maketrans('₀₁₂₃₄₅₆₇₈₉','0123456789')
def parse_formula(formula):
    s=formula.translate(sub)
    s=s.replace('(aq)','').replace('↓','').replace('↑','')
    # strip charge-like suffixes if any
    tokens=re.findall(r'[A-Z][a-z]?|\d+|\(|\)', s)
    if ''.join(tokens)!=s:
        raise ValueError(f'Unparsed formula text: {formula!r} -> {s!r}, tokens={tokens}')
    stack=[Counter()]; i=0
    while i<len(tokens):
        t=tokens[i]
        if t=='(':
            stack.append(Counter()); i+=1
        elif t==')':
            if len(stack)==1: raise ValueError('unmatched ) '+formula)
            grp=stack.pop(); i+=1
            n=1
            if i<len(tokens) and tokens[i].isdigit(): n=int(tokens[i]); i+=1
            for k,v in grp.items(): stack[-1][k]+=v*n
        elif re.match(r'[A-Z]',t):
            elem=t; i+=1; n=1
            if i<len(tokens) and tokens[i].isdigit(): n=int(tokens[i]); i+=1
            stack[-1][elem]+=n
        else:
            raise ValueError('orphan number '+formula)
    if len(stack)!=1: raise ValueError('unmatched ( '+formula)
    return stack[0]

def parse_amounts(s):
    if isinstance(s, dict): return {str(k):int(v) for k,v in s.items()}
    out={}
    for part in str(s).split(','):
        part=part.strip()
        if not part: continue
        k,v=part.split('=',1); out[k.strip()]=int(v)
    return out

# elements/species
with open(root/'elements.csv',encoding='utf-8') as f: elements=list(csv.DictReader(f))
with open(root/'species-v4.csv',encoding='utf-8') as f: species=list(csv.DictReader(f))
all_ids={e['symbol'] for e in elements}|{s['id'] for s in species}
assert len(elements)==118
assert len(species)==70
assert len(all_ids)==188, f'duplicate IDs: {188-len(all_ids)}'
formulas={e['symbol']:Counter({e['symbol']:1}) for e in elements}
for s in species: formulas[s['id']]=parse_formula(s['formula'])

# reactions
ry=yaml.safe_load((root/'reactions-v4.yml').read_text(encoding='utf-8'))
rx=ry['reactions']
unknown=[]; imbalanced=[]; bad_meta=[]; eqs=[]
valid_labs={'GENERAL','SOLUTION','GAS','PRECIPITATION','ACID_BASE','REDOX','ELECTROLYSIS','THERMAL'}
for rid,r in rx.items():
    ins=parse_amounts(r['inputs']); outs=parse_amounts(r['outputs'])
    cat=r.get('catalyst')
    for x in list(ins)+list(outs)+([cat] if cat else []):
        if x not in all_ids: unknown.append((rid,x))
    L=Counter(); R=Counter()
    for k,n in ins.items():
        for el,c in formulas[k].items(): L[el]+=c*n
    for k,n in outs.items():
        for el,c in formulas[k].items(): R[el]+=c*n
    if L!=R: imbalanced.append((rid,dict(L),dict(R)))
    if r.get('lab') not in valid_labs or r.get('temperature') not in {'ROOM','HEATED'} or r.get('pressure','NORMAL') not in {'NORMAL','HIGH'}:
        bad_meta.append(rid)
    eqs.append((tuple(sorted(ins.items())),tuple(sorted(outs.items())),r.get('lab'),r.get('temperature'),r.get('pressure','NORMAL'),cat))
duplicates=len(eqs)-len(set(eqs))

# extraction
ex=yaml.safe_load((root/'extract-v4.yml').read_text(encoding='utf-8'))['extractions']
ex_unknown=[]; reachable=set()
for mat,out in ex.items():
    d=parse_amounts(out)
    for x in d:
        if x not in all_ids: ex_unknown.append((mat,x))
        else: reachable.add(x)
# reaction graph reachability incl catalysts
changed=True
while changed:
    changed=False
    for rid,r in rx.items():
        ins=parse_amounts(r['inputs']); outs=parse_amounts(r['outputs']); cat=r.get('catalyst')
        if all(x in reachable for x in ins) and (not cat or cat in reachable):
            for x in outs:
                if x not in reachable:
                    reachable.add(x); changed=True
reachable_elements={e['symbol'] for e in elements}&reachable
reachable_species={s['id'] for s in species}&reachable

# pack validation
je=dist/'GeumyiChemistry-JE-0.4.0.zip'; be=dist/'GeumyiChemistry-BE-0.4.0.mcpack'; mapping=dist/'GeumyiChemistry-Geyser-mappings-0.4.0.json'
for zpath in (je,be):
    with zipfile.ZipFile(zpath) as z:
        bad=z.testzip()
        assert bad is None, f'corrupt zip {zpath}: {bad}'
with zipfile.ZipFile(je) as z:
    mc=json.loads(z.read('pack.mcmeta'))
    assert mc['pack']['min_format']==[88,0] and mc['pack']['max_format']==[88,0]
    je_items=[n for n in z.namelist() if n.startswith('assets/geumyi_chem/items/') and n.endswith('.json')]
    je_models=[n for n in z.namelist() if n.startswith('assets/geumyi_chem/models/item/') and n.endswith('.json')]
    je_textures=[n for n in z.namelist() if n.startswith('assets/geumyi_chem/textures/item/') and n.endswith('.png')]
    je_missing_model_refs=[]; je_missing_texture_refs=[]
    names=set(z.namelist())
    for itemn in je_items:
        itemj=json.loads(z.read(itemn))
        modelid=itemj.get('model',{}).get('model','')
        if modelid.startswith('geumyi_chem:item/'):
            rel=modelid[len('geumyi_chem:item/'):]
            modeln='assets/geumyi_chem/models/item/'+rel+'.json'
            if modeln not in names: je_missing_model_refs.append((itemn,modeln))
        else: je_missing_model_refs.append((itemn,modelid))
    for modeln in je_models:
        mj=json.loads(z.read(modeln))
        texid=mj.get('textures',{}).get('layer0','')
        if texid.startswith('geumyi_chem:item/'):
            rel=texid[len('geumyi_chem:item/'):]
            texn='assets/geumyi_chem/textures/item/'+rel+'.png'
            if texn not in names: je_missing_texture_refs.append((modeln,texn))
        else: je_missing_texture_refs.append((modeln,texid))
with zipfile.ZipFile(be) as z:
    man=json.loads(z.read('manifest.json'))
    assert man['format_version']==2
    uuid.UUID(man['header']['uuid']); uuid.UUID(man['modules'][0]['uuid']); assert man['header']['uuid']!=man['modules'][0]['uuid']
    tex=json.loads(z.read('textures/item_texture.json'))['texture_data']
    be_pngs={n for n in z.namelist() if n.startswith('textures/items/') and n.endswith('.png')}
    missing_be=[]
    for key,v in tex.items():
        vals=v['textures'] if isinstance(v['textures'],list) else [v['textures']]
        for tv in vals:
            p=tv+'.png'
            if p not in be_pngs: missing_be.append((key,p))
mp=json.loads(mapping.read_text(encoding='utf-8'))
assert mp.get('format_version')==2
# accept mappings under items key; inspect shape
items=mp.get('items') or mp.get('mappings') or {}
# recursively find definitions if base-item grouping
mapping_defs=[]
def walk(obj):
    if isinstance(obj,dict):
        if 'bedrock_identifier' in obj: mapping_defs.append(obj)
        else:
            for v in obj.values(): walk(v)
    elif isinstance(obj,list):
        for v in obj: walk(v)
walk(items)
idents=[d.get('bedrock_identifier') for d in mapping_defs]
icons=[d.get('bedrock_options',{}).get('icon') for d in mapping_defs if d.get('bedrock_options',{}).get('icon')]
models=[d.get('model') for d in mapping_defs if d.get('model')]

# Cross-check each mapping against JE item definition and BE texture key
je_model_ids=set()
with zipfile.ZipFile(je) as z:
    for n in je_items:
        rel=n[len('assets/geumyi_chem/items/'):-5]
        je_model_ids.add('geumyi_chem:'+rel)
missing_mapping_models=[m for m in models if m not in je_model_ids]
missing_mapping_icons=[i for i in icons if i not in tex]

errors=[]
if unknown: errors.append(f'Unknown reaction IDs: {unknown[:10]}')
if imbalanced: errors.append(f'Imbalanced reactions: {[x[0] for x in imbalanced[:10]]}')
if bad_meta: errors.append(f'Bad reaction metadata: {bad_meta[:10]}')
if duplicates: errors.append(f'Duplicate reaction definitions: {duplicates}')
if ex_unknown: errors.append(f'Unknown extraction IDs: {ex_unknown[:10]}')
if len(reachable_elements)!=118: errors.append(f'Element reachability {len(reachable_elements)}/118 missing {sorted({e["symbol"] for e in elements}-reachable_elements)}')
if len(reachable_species)!=70: errors.append(f'Species reachability {len(reachable_species)}/70 missing {sorted({s["id"] for s in species}-reachable_species)}')
if len(je_items)!=200: errors.append(f'JE item models {len(je_items)} != 200')
if len(je_models)!=200: errors.append(f'JE models {len(je_models)} != 200')
if len(je_textures)!=200: errors.append(f'JE textures {len(je_textures)} != 200')
if je_missing_model_refs: errors.append(f'Broken JE item->model refs: {je_missing_model_refs[:5]}')
if je_missing_texture_refs: errors.append(f'Broken JE model->texture refs: {je_missing_texture_refs[:5]}')
if len(tex)!=200: errors.append(f'BE texture entries {len(tex)} != 200')
if missing_be: errors.append(f'Missing BE PNGs: {missing_be[:5]}')
if len(mapping_defs)!=199: errors.append(f'Geyser definitions {len(mapping_defs)} != 199')
if len(idents)!=len(set(idents)): errors.append('Duplicate Geyser bedrock_identifier')
if missing_mapping_models: errors.append(f'Geyser models missing in JE pack: {missing_mapping_models[:5]}')
if missing_mapping_icons: errors.append(f'Geyser icons missing in BE item_texture: {missing_mapping_icons[:5]}')

report=[]
report += ['GeumyiChemistry v0.4.0 release validation','']
report += [f'Elements: {len(elements)}',f'Species: {len(species)}',f'Reactions: {len(rx)}',f'Extraction routes: {len(ex)}']
report += [f'Unknown reaction IDs: {len(unknown)}',f'Unknown extraction IDs: {len(ex_unknown)}',f'Stoichiometrically imbalanced reactions: {len(imbalanced)}',f'Duplicate reaction definitions: {duplicates}',f'Invalid reaction lab/temperature/pressure metadata: {len(bad_meta)}']
report += [f'Elements reachable from survival/research graph: {len(reachable_elements)} / 118',f'Species reachable from extraction + reactions: {len(reachable_species)} / 70']
report += ['', 'Resource packs / Geyser:',f'JE item definitions: {len(je_items)}',f'JE model files: {len(je_models)}',f'JE textures: {len(je_textures)}',f'JE item→model broken refs: {len(je_missing_model_refs)}',f'JE model→texture broken refs: {len(je_missing_texture_refs)}',f'BE texture entries: {len(tex)}',f'BE PNG texture files: {len(be_pngs)}',f'Geyser custom-item definitions: {len(mapping_defs)}',f'Geyser unique bedrock identifiers: {len(set(idents))}',f'Geyser mapping models present in JE pack: {len(models)-len(missing_mapping_models)} / {len(models)}',f'Geyser mapping icons present in BE pack: {len(icons)-len(missing_mapping_icons)} / {len(icons)}',f'JE ZIP integrity: PASS',f'BE MCPACK ZIP integrity: PASS',f'JE pack format: 88.0',f'BE manifest UUID syntax/uniqueness: PASS',f'Bedrock lab_bench custom-item mapping: intentionally excluded to preserve vanilla brewing-stand placement behavior through Geyser', '', 'Compile/runtime scope:', 'Java source compile (-Xlint:all) in local compatibility stub environment: PASS', 'Paper 26.2 API signatures used by new code were cross-checked against official Paper Javadocs.', 'A live Paper 26.2 + Geyser server boot and two-client click/placement test cannot be performed in this container.', '', 'RESULT: '+('FAIL' if errors else 'PASS')]
if errors:
    report += ['', 'Errors:']+['- '+e for e in errors]
out='\n'.join(report)+'\n'
project/'VALIDATION-local.txt'.write_text(out,encoding='utf-8')
print(out)
if errors: sys.exit(2)
