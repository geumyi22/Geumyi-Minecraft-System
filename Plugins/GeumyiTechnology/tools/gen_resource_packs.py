from pathlib import Path
from PIL import Image, ImageDraw
import json, shutil, zipfile, uuid

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'packs'
JE=OUT/'je'
BE=OUT/'be'
for p in [JE,BE]:
    if p.exists(): shutil.rmtree(p)
    p.mkdir(parents=True)

items = [
('tech_manual','book','tool'),('tech_workbench','crafting_table','block'),
('copper_wire','string','component'),('machine_frame','heavy_weighted_pressure_plate','component'),
('basic_circuit','comparator','component'),('electric_motor','piston','component'),
('heating_coil','tripwire_hook','component'),('battery_cell','redstone_torch','component'),
('high_density_cell','echo_shard','component'),
('iron_dust','gunpowder','material'),('copper_dust','orange_dye','material'),('gold_dust','yellow_dye','material'),
('silicon_dust','sugar','material'),('silicon_wafer','quartz','material'),
('power_cable','chain','block'),('coal_generator','furnace','block'),('solar_panel','daylight_detector','block'),
('battery_box','barrel','block'),('battery_box_mk2','ender_chest','block'),('crusher','blast_furnace','block'),
('electric_furnace','smoker','block'),('electrolyzer','crafter','block')]

# Pixel-art palette
COLORS={
 'bg':(18,22,30,0), 'dark':(28,34,45,255), 'metal':(150,165,175,255), 'light':(220,235,240,255),
 'copper':(205,105,58,255), 'copper2':(235,142,82,255), 'blue':(45,170,230,255), 'cyan':(70,225,235,255),
 'yellow':(240,205,70,255), 'red':(220,65,60,255), 'green':(70,200,120,255), 'purple':(160,95,220,255),
 'black':(24,24,28,255), 'white':(245,245,245,255), 'orange':(235,135,50,255), 'gold':(244,190,45,255),
}

def px(draw, box, color): draw.rectangle(box, fill=color)

def base_icon(item_id):
    im=Image.new('RGBA',(32,32),(0,0,0,0)); d=ImageDraw.Draw(im)
    # shared soft plate for readability
    if item_id in {'tech_workbench','coal_generator','solar_panel','battery_box','battery_box_mk2','crusher','electric_furnace','electrolyzer'}:
        px(d,(5,6,26,27),COLORS['dark']); px(d,(7,4,24,6),COLORS['metal']); px(d,(7,27,24,29),COLORS['metal'])
    if item_id=='tech_manual':
        px(d,(5,6,15,25),COLORS['blue']); px(d,(16,6,26,25),COLORS['cyan']); px(d,(15,7,16,25),COLORS['white']); px(d,(8,9,13,10),COLORS['white']); px(d,(19,9,24,10),COLORS['white'])
    elif item_id=='tech_workbench':
        px(d,(7,8,24,20),COLORS['copper']); px(d,(9,10,22,18),COLORS['metal']); px(d,(10,20,12,27),COLORS['copper2']); px(d,(19,20,21,27),COLORS['copper2']); px(d,(13,12,18,16),COLORS['blue'])
    elif item_id=='copper_wire':
        d.ellipse((6,6,25,25),outline=COLORS['copper2'],width=5); d.ellipse((11,11,20,20),outline=COLORS['dark'],width=2); px(d,(21,22,28,24),COLORS['copper2'])
    elif item_id=='machine_frame':
        px(d,(5,5,26,8),COLORS['metal']); px(d,(5,23,26,26),COLORS['metal']); px(d,(5,8,8,23),COLORS['metal']); px(d,(23,8,26,23),COLORS['metal']); px(d,(10,10,21,21),COLORS['dark']); px(d,(14,14,17,17),COLORS['blue'])
    elif item_id=='basic_circuit':
        px(d,(6,7,25,24),COLORS['green']); px(d,(9,10,22,21),COLORS['dark']); px(d,(12,12,18,18),COLORS['blue']);
        for x,y in [(8,9),(23,9),(8,22),(23,22),(15,8),(15,23)]: px(d,(x,y,x+1,y+1),COLORS['gold'])
    elif item_id=='electric_motor':
        px(d,(7,9,24,22),COLORS['metal']); d.ellipse((9,10,22,21),fill=COLORS['copper']); d.ellipse((13,13,18,18),fill=COLORS['dark']); px(d,(24,13,28,17),COLORS['metal'])
    elif item_id=='heating_coil':
        for y in [8,12,16,20,24]: px(d,(7,y,24,y+2),COLORS['orange']); px(d,(5,7,8,26),COLORS['metal']); px(d,(23,7,26,26),COLORS['metal'])
    elif item_id in {'battery_cell','high_density_cell'}:
        c=COLORS['green'] if item_id=='battery_cell' else COLORS['purple']; px(d,(9,5,22,26),COLORS['dark']); px(d,(11,7,20,24),c); px(d,(13,3,18,6),COLORS['metal']); px(d,(14,11,17,15),COLORS['white']); px(d,(12,13,19,14),COLORS['white'])
    elif item_id.endswith('_dust'):
        c={'iron_dust':COLORS['metal'],'copper_dust':COLORS['copper2'],'gold_dust':COLORS['gold'],'silicon_dust':COLORS['light']}[item_id]
        for box in [(5,20,13,25),(11,13,20,24),(18,18,27,25),(8,17,18,26)]: d.ellipse(box,fill=c)
    elif item_id=='silicon_wafer':
        d.ellipse((5,5,26,26),fill=COLORS['cyan'],outline=COLORS['metal'],width=2); px(d,(14,6,16,25),COLORS['white']); px(d,(6,14,25,16),COLORS['white'])
    elif item_id=='power_cable':
        px(d,(4,13,27,18),COLORS['black']); px(d,(6,14,25,17),COLORS['copper2']); px(d,(3,11,7,20),COLORS['metal']); px(d,(24,11,28,20),COLORS['metal'])
    elif item_id=='coal_generator':
        px(d,(8,8,23,24),COLORS['metal']); px(d,(10,11,21,20),COLORS['black']); px(d,(12,14,19,21),COLORS['orange']); px(d,(11,6,20,9),COLORS['copper'])
    elif item_id=='solar_panel':
        px(d,(6,8,25,22),COLORS['blue']);
        for x in [8,13,18,23]: px(d,(x,9,x+1,21),COLORS['cyan'])
        for y in [12,17]: px(d,(7,y,24,y+1),COLORS['cyan'])
        px(d,(14,22,17,27),COLORS['metal'])
    elif item_id in {'battery_box','battery_box_mk2'}:
        c=COLORS['green'] if item_id=='battery_box' else COLORS['purple']; px(d,(7,8,24,25),COLORS['metal']); px(d,(9,10,22,23),c); px(d,(13,12,18,19),COLORS['white']); px(d,(11,15,20,17),COLORS['white'])
    elif item_id=='crusher':
        px(d,(7,8,24,24),COLORS['metal']); d.ellipse((10,11,21,22),fill=COLORS['dark']);
        for a in [(14,8,17,12),(14,21,17,25),(7,14,11,17),(20,14,24,17)]: px(d,a,COLORS['copper2'])
    elif item_id=='electric_furnace':
        px(d,(7,8,24,24),COLORS['metal']); px(d,(10,11,21,21),COLORS['dark']); px(d,(12,13,19,20),COLORS['orange']); px(d,(8,6,23,9),COLORS['red'])
    elif item_id=='electrolyzer':
        px(d,(7,8,24,24),COLORS['metal']); px(d,(9,10,15,22),COLORS['blue']); px(d,(17,10,22,22),COLORS['cyan']); px(d,(11,6,20,9),COLORS['purple']); px(d,(15,13,17,18),COLORS['white'])
    return im

# JE
(JE/'assets/geumyi_tech/items/item').mkdir(parents=True)
(JE/'assets/geumyi_tech/models/item').mkdir(parents=True)
(JE/'assets/geumyi_tech/textures/item').mkdir(parents=True)
(JE/'pack.mcmeta').write_text(json.dumps({'pack':{'description':'Geumyi Technology v0.1.0 · Java 26.2','min_format':[88,0],'max_format':[88,0]}},ensure_ascii=False,indent=2),encoding='utf8')

# BE
(BE/'textures/items').mkdir(parents=True)
texdata={}

for item_id,base,kind in items:
    im=base_icon(item_id)
    im.save(JE/f'assets/geumyi_tech/textures/item/{item_id}.png')
    (JE/f'assets/geumyi_tech/items/item/{item_id}.json').write_text(json.dumps({'model':{'type':'minecraft:model','model':f'geumyi_tech:item/{item_id}'}},indent=2),encoding='utf8')
    (JE/f'assets/geumyi_tech/models/item/{item_id}.json').write_text(json.dumps({'parent':'minecraft:item/generated','textures':{'layer0':f'geumyi_tech:item/{item_id}'}},indent=2),encoding='utf8')
    im.save(BE/f'textures/items/{item_id}.png')
    texdata[f'geumyi_tech:{item_id}']={'textures':[f'textures/items/{item_id}']}

# icons
pack_icon=Image.new('RGBA',(128,128),(18,22,30,255)); d=ImageDraw.Draw(pack_icon); d.rectangle((16,16,111,111),outline=COLORS['cyan'],width=7); d.line((34,86,94,42),fill=COLORS['copper2'],width=12); d.ellipse((45,35,86,76),outline=COLORS['blue'],width=8); d.rectangle((56,81,72,106),fill=COLORS['green']); pack_icon.save(JE/'pack.png'); pack_icon.save(BE/'pack_icon.png')

manifest={'format_version':2,'header':{'description':'Geumyi Technology v0.1.0 · Geyser/Bedrock icons','name':'Geumyi Technology BE 0.1.0','uuid':str(uuid.uuid5(uuid.NAMESPACE_DNS,'geumyi-tech-be-header-0.1.0')),'version':[0,1,0],'min_engine_version':[1,20,0]},'modules':[{'description':'Geumyi Technology Bedrock resources','type':'resources','uuid':str(uuid.uuid5(uuid.NAMESPACE_DNS,'geumyi-tech-be-module-0.1.0')),'version':[0,1,0]}]}
(BE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
(BE/'textures/item_texture.json').write_text(json.dumps({'resource_pack_name':'Geumyi Technology BE 0.1.0','texture_name':'atlas.items','texture_data':texdata},ensure_ascii=False,indent=2),encoding='utf8')

# Geyser mapping: exclude placeable block items to preserve Bedrock block placement behavior.
mapping={'format_version':2,'items':{}}
for item_id,base,kind in items:
    if kind=='block': continue
    java=f'minecraft:{base}'
    mapping['items'].setdefault(java,[]).append({'type':'definition','model':f'geumyi_tech:item/{item_id}','bedrock_identifier':f'geumyi_tech:{item_id}','display_name':f'[TECH] {item_id}','bedrock_options':{'icon':f'geumyi_tech:{item_id}','creative_category':'items'}})
(OUT/'GeumyiTechnology-Geyser-mappings-0.1.0.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf8')

# Zip packs
def zipdir(src,dest):
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob('*')):
            if f.is_file(): z.write(f,f.relative_to(src).as_posix())
zipdir(JE, OUT/'GeumyiTechnology-JE-0.1.0.zip')
zipdir(BE, OUT/'GeumyiTechnology-BE-0.1.0.mcpack')

# Preview sheet
cols=6; cell=72; rows=(len(items)+cols-1)//cols
sheet=Image.new('RGBA',(cols*cell,rows*cell),(24,28,36,255))
d=ImageDraw.Draw(sheet)
for idx,(item_id,_,kind) in enumerate(items):
    x=(idx%cols)*cell; y=(idx//cols)*cell
    icon=base_icon(item_id).resize((48,48),resample=Image.Resampling.NEAREST)
    sheet.alpha_composite(icon,(x+12,y+4))
    # compact label hash blocks; file names are available separately
    d.rectangle((x+7,y+56,x+65,y+66),fill=(40,48,60,255))
    hue={'tool':COLORS['green'],'component':COLORS['blue'],'material':COLORS['yellow'],'block':COLORS['copper2']}[kind]
    d.rectangle((x+9,y+58,x+9+min(52,len(item_id)*3),y+63),fill=hue)
sheet.save(OUT/'ICON-PREVIEW.png')
print('Generated',len(items),'JE icons,',sum(1 for i in items if i[2]!='block'),'Bedrock mapped custom items')
