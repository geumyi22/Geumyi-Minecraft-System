'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const html=fs.readFileSync(path.join(__dirname,'../../GSC/ServerCenter/cmd/client/dashboard.html'),'utf8');
const js=html.slice(html.indexOf('let settingsReadSequence='),html.indexOf('function browseServerSetting('));
const form={inert:false,innerHTML:'',setAttribute(){},removeAttribute(){}};
const save={disabled:false},feedback={textContent:''},url={defaultValue:'http://old',value:'http://new'};
const token={defaultValue:'',value:''};
const controls={settingsBody:form,saveSettingsButton:save,settingsMsg:feedback,setHostURL:url,setToken:token,
  setUIScale:{value:'comfortable'},setAgentAuto:{checked:true}};
let posted=[],requests=[],online=true,read;
const ctx=vm.createContext({
  $:id=>controls[id],koMessage:s=>s,esc:x=>String(x||''),serverIcon:()=>'',
  localStorage:{getItem:()=>''},toast(){},applyUIScale(){},refreshStatus(){},
  req:async(endpoint,opt={})=>{
    requests.push(endpoint);
    if(opt.method==='POST'){posted.push({endpoint,payload:JSON.parse(opt.body)});return {};}
    if(endpoint==='/client/config')return {host_url:'http://new',token:''};
    if(read)return new Promise(resolve=>{read.push(resolve)});
    if(!online)throw new Error('offline');
    return {servers:[]};
  },
  hostSettings:{servers:[]}
});
vm.runInContext(js,ctx);
async function test(){
  await vm.runInContext('saveSettings()',ctx);
  assert.deepEqual(posted.map(x=>x.endpoint),['/client/config'],'changing connection must not write old server settings to the new Host');
  url.defaultValue=url.value;posted=[];
  await vm.runInContext('saveSettings()',ctx);
  assert.deepEqual(posted.map(x=>x.endpoint),['/api/settings']);
  online=false;await vm.runInContext('loadSettings()',ctx);
  assert.match(form.innerHTML,/id="setHostURL"/);assert.doesNotMatch(form.innerHTML,/id="setAgentAuto"/);
  assert.equal(save.disabled,false);
  read=[];
  const earlier=vm.runInContext('loadSettings()',ctx),later=vm.runInContext('loadSettings()',ctx);
  assert.ok(form.inert&&save.disabled,'stale form is not editable while loading');
  read[1]({servers:[],bind:'latest-host'});await later;
  read[0]({servers:[],bind:'stale-host'});await earlier;
  assert.match(form.innerHTML,/latest-host/);assert.doesNotMatch(form.innerHTML,/stale-host/);
  console.log('PASS Client connection change, offline connection settings, stale edit lock, and out-of-order reads');
}
test().catch(e=>{console.error(e);process.exitCode=1});
