from pathlib import Path
import csv, json, re, uuid, zipfile, shutil, hashlib
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'src/main/resources'
OUT=ROOT/'dist'
JE=OUT/'GeumyiChemistry-JE-0.4.0'
BE=OUT/'GeumyiChemistry-BE-0.4.0'
for p in (JE,BE):
    if p.exists(): shutil.rmtree(p)
    p.mkdir(parents=True)

# fonts are used internally only; not distributed.
def load_font(size,bold=False):
    candidates=[]
    if bold:
        candidates += ['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf','/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf']
    else:
        candidates += ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf','/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf']
    for c in candidates:
        if Path(c).exists(): return ImageFont.truetype(c,size)
    return ImageFont.load_default()

F6=load_font(6); F7=load_font(7); F8=load_font(8); F9=load_font(9,True); F11=load_font(11,True); F14=load_font(14,True)

def safe_id(s):
    return re.sub(r'[^a-z0-9._/-]','_',s.lower())

def rgb(hexv): return tuple(int(hexv[i:i+2],16) for i in (0,2,4))
CAT_COL={
 'nonmetal':'4D9DE0','noble':'9B5DE5','alkali':'F15BB5','alkaline':'FEE440','metalloid':'00BBF9',
 'halogen':'00F5D4','transition':'F8961E','post':'90BE6D','lanthanide':'F9844A','actinide':'F94144',
}
STATE_COL={'GAS':'BDE0FE','LIQUID':'4CC9F0','AQUEOUS':'4895EF','PRECIPITATE':'FFD166','SOLID':'CDB4DB','ELEMENT':'80ED99'}

def outlined_text(draw,xy,text,font,fill=(255,255,255,255),stroke=(0,0,0,255),sw=1,anchor=None):
    draw.text(xy,text,font=font,fill=fill,stroke_width=sw,stroke_fill=stroke,anchor=anchor)

def element_icon(row):
    im=Image.new('RGBA',(32,32),(0,0,0,0)); d=ImageDraw.Draw(im)
    c=rgb(CAT_COL.get(row['category'],'6C757D'))
    d.rounded_rectangle((2,2,29,29),radius=4,fill=c+(255,),outline=(25,30,35,255),width=2)
    # top highlight
    d.line((5,5,26,5),fill=(255,255,255,100),width=1)
    outlined_text(d,(5,5),row['atomic'],F6,anchor='la')
    sym=row['symbol']
    font=F14 if len(sym)<=2 else F11
    outlined_text(d,(16,17),sym,font,anchor='mm')
    return im

def species_icon(row):
    im=Image.new('RGBA',(32,32),(0,0,0,0)); d=ImageDraw.Draw(im)
    state=row.get('state','SOLID') or 'SOLID'
    c=rgb(STATE_COL.get(state,'CDB4DB'))
    # flask silhouette
    d.polygon([(12,3),(20,3),(20,10),(27,24),(27,27),(5,27),(5,24),(12,10)],fill=(230,240,245,230),outline=(25,30,35,255))
    d.rectangle((12,3,20,8),fill=(220,230,235,255),outline=(25,30,35,255))
    d.polygon([(7,21),(25,21),(27,26),(5,26)],fill=c+(240,))
    # state indication
    if state=='GAS':
        for x,y in [(9,19),(15,16),(21,18)]: d.ellipse((x,y,x+2,y+2),fill=c+(220,))
    elif state=='PRECIPITATE':
        d.ellipse((9,22,23,25),fill=c+(255,))
    text=row['formula']
    # replace unicode subscripts if font/layout overflows; retain common formula appearance where possible.
    font=F8 if len(text)<=6 else F6
    outlined_text(d,(16,14),text,font,anchor='mm')
    return im

def tool_icon(tool_id):
    im=Image.new('RGBA',(32,32),(0,0,0,0)); d=ImageDraw.Draw(im)
    edge=(25,30,35,255); glass=(200,235,255,210); metal=(155,165,175,255); copper=(184,115,51,255); red=(220,50,47,255)
    if tool_id in ('lab_kit','lab_bench'):
        d.rounded_rectangle((4,7,27,27),3,fill=(62,78,92,255),outline=edge,width=2)
        d.rectangle((8,3,23,10),fill=(90,110,125,255),outline=edge)
        d.polygon([(11,11),(16,8),(21,11),(23,23),(9,23)],fill=glass,outline=edge)
        d.rectangle((11,19,21,23),fill=(72,202,228,230))
    elif tool_id in ('beaker','test_tube'):
        if tool_id=='beaker':
            d.polygon([(8,5),(24,5),(22,27),(10,27)],fill=glass,outline=edge)
            d.rectangle((10,20,22,26),fill=(72,202,228,230))
            d.line((8,8,24,8),fill=edge,width=2)
        else:
            for x,col in [(9,(72,202,228,240)),(16,(255,209,102,240)),(23,(247,37,133,230))]:
                d.rounded_rectangle((x-3,4,x+2,27),2,fill=glass,outline=edge)
                d.rectangle((x-2,18,x+1,25),fill=col)
    elif tool_id=='gas_collector':
        d.ellipse((6,5,25,24),fill=glass,outline=edge,width=2)
        d.rectangle((13,2,18,7),fill=metal,outline=edge)
        for x,y in [(10,15),(16,11),(20,17)]: d.ellipse((x,y,x+2,y+2),fill=(255,255,255,230))
    elif tool_id=='heater':
        d.rounded_rectangle((5,8,27,27),2,fill=metal,outline=edge,width=2)
        d.rectangle((9,11,23,19),fill=(30,30,30,255),outline=edge)
        d.polygon([(16,12),(12,18),(16,17),(19,20),(21,15)],fill=(255,120,30,255))
        d.ellipse((9,22,12,25),fill=red); d.ellipse((20,22,23,25),fill=(70,220,100,255))
    elif tool_id=='electrolyzer':
        d.rounded_rectangle((5,6,27,27),2,fill=glass,outline=edge,width=2)
        d.line((11,3,11,23),fill=copper,width=2); d.line((21,3,21,23),fill=copper,width=2)
        d.line((11,4,21,4),fill=red,width=1)
        for x,y in [(10,19),(12,15),(20,18),(21,13)]: d.ellipse((x,y,x+2,y+2),fill=(255,255,255,235))
    elif tool_id=='filter':
        d.polygon([(5,5),(27,5),(20,16),(20,27),(12,27),(12,16)],fill=glass,outline=edge,width=2)
        d.polygon([(8,8),(24,8),(18,15),(14,15)],fill=(222,184,135,255))
    elif tool_id=='distiller':
        d.ellipse((4,15,17,28),fill=glass,outline=edge)
        d.line((11,15,11,7),fill=edge,width=2); d.line((11,7,23,7),fill=edge,width=2); d.line((23,7,23,17),fill=edge,width=2)
        d.ellipse((19,16,28,26),fill=glass,outline=edge); d.ellipse((7,21,14,26),fill=(72,202,228,220))
    elif tool_id=='scale':
        d.rectangle((5,24,27,28),fill=metal,outline=edge); d.line((16,6,16,24),fill=metal,width=2)
        d.line((7,10,25,10),fill=metal,width=2); d.line((9,10,6,18),fill=metal); d.line((23,10,26,18),fill=metal)
        d.arc((3,15,11,22),0,180,fill=edge,width=2); d.arc((21,15,29,22),0,180,fill=edge,width=2)
    elif tool_id=='pressure_chamber':
        d.rounded_rectangle((6,5,26,27),5,fill=metal,outline=edge,width=2); d.ellipse((10,9,22,21),fill=(30,45,55,255),outline=edge)
        d.line((16,15,20,12),fill=red,width=2); d.ellipse((14,13,18,17),fill=(240,240,240,255))
    elif tool_id=='ph_paper':
        d.polygon([(6,4),(25,7),(22,28),(4,24)],fill=(245,245,230,255),outline=edge)
        cols=[(220,50,47),(245,160,30),(240,220,50),(80,190,100),(65,140,220),(120,80,190)]
        for i,c in enumerate(cols): d.rectangle((9,7+i*3,21,9+i*3),fill=c+(255,))
    else:
        d.rounded_rectangle((4,4,28,28),4,fill=(85,120,150,255),outline=edge,width=2)
        outlined_text(d,(16,16),'C',F14,anchor='mm')
    return im

# data
with open(SRC/'elements.csv',encoding='utf-8-sig',newline='') as f: elements=list(csv.DictReader(f))
with open(SRC/'species-v4.csv',encoding='utf-8-sig',newline='') as f: species=list(csv.DictReader(f))

java=Path(ROOT/'src/main/java/kr/geumyi/chemistry/GeumyiChemistry.java').read_text(encoding='utf-8')
tool_pat=re.compile(r'add\("([^"]+)","([^"]+)","([^"]+)"')
tools=[]
for tid,name,mat in tool_pat.findall(java):
    if tid not in {x['id'] for x in tools}: tools.append({'id':tid,'name':name,'material':mat})

# Java pack metadata
(JE/'pack.mcmeta').write_text(json.dumps({'pack':{'description':'Geumyi Chemistry v0.4.0 · Java 26.2','min_format':[88,0],'max_format':[88,0]}},ensure_ascii=False,indent=2),encoding='utf-8')
# pack icons
pack_icon=Image.new('RGBA',(64,64),(18,32,42,255)); d=ImageDraw.Draw(pack_icon)
d.rounded_rectangle((8,8,56,56),8,fill=(36,74,92,255),outline=(160,235,245,255),width=3)
d.polygon([(23,12),(41,12),(39,28),(50,51),(14,51),(25,28)],fill=(210,245,250,230),outline=(10,20,25,255))
d.polygon([(18,43),(46,43),(50,51),(14,51)],fill=(39,200,210,240)); outlined_text(d,(32,34),'C',F14,anchor='mm')
pack_icon.save(JE/'pack.png')

je_entries={}
be_entries={}
base_map={}

def write_java(kind,sid,img):
    mid=f'{kind}/{safe_id(sid)}'
    itemdef=JE/f'assets/geumyi_chem/items/{mid}.json'; itemdef.parent.mkdir(parents=True,exist_ok=True)
    itemdef.write_text(json.dumps({'model':{'type':'minecraft:model','model':f'geumyi_chem:item/{mid}'}},indent=2),encoding='utf-8')
    model=JE/f'assets/geumyi_chem/models/item/{mid}.json'; model.parent.mkdir(parents=True,exist_ok=True)
    model.write_text(json.dumps({'parent':'minecraft:item/generated','textures':{'layer0':f'geumyi_chem:item/{mid}'}},indent=2),encoding='utf-8')
    tex=JE/f'assets/geumyi_chem/textures/item/{mid}.png'; tex.parent.mkdir(parents=True,exist_ok=True); img.save(tex)
    je_entries[f'geumyi_chem:{mid}']=str(tex.relative_to(JE))

def add_bedrock(base_material,kind,sid,display,img,allow=True):
    mid=f'{kind}/{safe_id(sid)}'
    bid=f'geumyi_chem:{kind}_{safe_id(sid).replace("/","_")}'
    icon=bid
    texrel=f'textures/items/{kind}_{safe_id(sid).replace("/","_")}'
    texpng=BE/(texrel+'.png'); texpng.parent.mkdir(parents=True,exist_ok=True); img.save(texpng)
    be_entries[icon]={'textures':[texrel]}
    if allow:
        jbase='minecraft:'+base_material.lower()
        base_map.setdefault(jbase,[]).append({
            'type':'definition','model':f'geumyi_chem:{mid}','bedrock_identifier':bid,'display_name':display,
            'bedrock_options':{'icon':icon,'creative_category':'items'}
        })

for r in elements:
    img=element_icon(r); sid=r['symbol']; write_java('element',sid,img)
    add_bedrock(r['material'],'element',sid,f"[CHEM] {r['symbol']} {r['korean']}",img)
for r in species:
    img=species_icon(r); sid=r['id']; write_java('species',sid,img)
    add_bedrock(r['material'],'species',sid,f"[CHEM] {r['formula']} {r['korean']}",img)
for r in tools:
    img=tool_icon(r['id']); write_java('tool',r['id'],img)
    # lab_bench is intentionally not custom-mapped on Bedrock to preserve vanilla brewing stand placement semantics.
    add_bedrock(r['material'],'tool',r['id'],f"[CHEM] {r['name']}",img,allow=(r['id']!='lab_bench'))

# Bedrock pack
header_uuid=str(uuid.uuid4()); module_uuid=str(uuid.uuid4())
manifest={'format_version':2,'header':{'description':'Geumyi Chemistry v0.4.0 · Geyser/Bedrock icons','name':'Geumyi Chemistry BE 0.4.0','uuid':header_uuid,'version':[0,4,0],'min_engine_version':[1,20,0]},'modules':[{'description':'Geumyi Chemistry Bedrock resources','type':'resources','uuid':module_uuid,'version':[0,4,0]}]}
(BE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
pack_icon.save(BE/'pack_icon.png')
(BE/'textures/item_texture.json').write_text(json.dumps({'resource_pack_name':'Geumyi Chemistry BE 0.4.0','texture_name':'atlas.items','texture_data':be_entries},ensure_ascii=False,indent=2),encoding='utf-8')

mapping={'format_version':2,'items':base_map}
(OUT/'GeumyiChemistry-Geyser-mappings-0.4.0.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')

# zip helper ensuring root layout
def makezip(folder,target):
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(folder.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(folder).as_posix())

makezip(JE,OUT/'GeumyiChemistry-JE-0.4.0.zip')
makezip(BE,OUT/'GeumyiChemistry-BE-0.4.0.mcpack')

meta={
 'elements':len(elements),'species':len(species),'tools':len(tools),'java_models':len(je_entries),
 'bedrock_texture_entries':len(be_entries),'geyser_definitions':sum(map(len,base_map.values())),
 'geyser_base_items':len(base_map),'bedrock_lab_bench_mapping_excluded':True,
 'be_header_uuid':header_uuid,'be_module_uuid':module_uuid
}
(OUT/'resource-pack-build.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(meta,ensure_ascii=False,indent=2))
