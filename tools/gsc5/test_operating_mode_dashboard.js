'use strict';

// Execute the shipped page handlers with isolated DOM elements and local API doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../../GSC/ServerCenter/cmd/client/dashboard.html'), 'utf8');
const nav = html.match(/<nav class="nav">([\s\S]*?)<\/nav>/)[1];
assert.equal([...nav.matchAll(/data-view="([^"]+)"/g)].at(-1)[1], 'risk');
assert.match(html, /if\(v==='risk'\)loadOperatingMode\(\)/);
assert.match(html, /id="operatingModeOpen"[^>]*disabled/);
const source = html.slice(html.indexOf('let openingOperatingMode='), html.indexOf('function loadView('));
new vm.Script(html.match(/<script>([\s\S]*?)<\/script>/)[1]);

async function check() {
  const controls = Object.fromEntries(['Open','Manual','Restore','Refresh','Availability','Message','HostStart','ClientStart']
    .map(key => ['operatingMode'+key,{disabled:key==='Open',textContent:''}]));
  const calls = [];
  let status = {available:true,version:'3.0.1',host_start_type:'delayed-automatic',client_autostart:'registered'};
  let launch;
  const context = vm.createContext({
    $:id=>controls[id],
    fetch:async (url,options)=>{
      calls.push({url,options});
      if (url==='/client/operating-mode/status') return {ok:true,json:async()=>status};
      assert.equal(url,'/client/operating-mode/open');
      await new Promise(resolve=>{launch=resolve});
      return {ok:true,json:async()=>({ok:true})};
    }
  });
  vm.runInContext(source,context);
  const invoke = name=>vm.runInContext(name+'()',context);
  await invoke('loadOperatingMode');
  assert.equal(calls.length,1);
  assert.equal(calls[0].url,'/client/operating-mode/status');
  assert.equal(controls.operatingModeHostStart.textContent,'자동 (지연된 시작)');
  assert.match(controls.operatingModeAvailability.textContent,/3\.0\.1/);
  assert.equal(controls.operatingModeClientStart.textContent,'등록됨');
  assert.equal(controls.operatingModeOpen.disabled,false);
  const result=invoke('openOperatingMode');
  await invoke('openOperatingMode');
  assert.equal(calls.length,2,'repeated click while opening');
  assert.equal(calls[1].options.method,'POST');
  assert.equal(calls[1].options.headers['X-GSC-Intent'],'open-operating-mode');
  assert.deepEqual(JSON.parse(calls[1].options.body),{});
  launch(); await result;
  for(const view of ['manual','restore']){
    const request=vm.runInContext('openOperatingMode('+JSON.stringify(view)+')',context);
    assert.equal(controls.operatingModeManual.disabled,true);
    assert.equal(controls.operatingModeRestore.disabled,true);
    const last=calls.at(-1);assert.equal(last.url,'/client/operating-mode/open');
    assert.deepEqual(JSON.parse(last.options.body),{view});
    launch();await request;
  }
  const previousCalls=calls.length;
  await vm.runInContext("openOperatingMode('invalid')",context);
  assert.equal(calls.length,previousCalls);
  status={available:false,host_start_type:'manual',client_autostart:'absent'};
  await invoke('loadOperatingMode');
  assert.equal(controls.operatingModeHostStart.textContent,'수동');
  assert.equal(controls.operatingModeClientStart.textContent,'미등록');
  assert.equal(controls.operatingModeOpen.disabled,true);
  await invoke('openOperatingMode');
  assert.equal(calls.length,previousCalls+1);
  status={available:false,host_start_type:'unknown',client_autostart:'unknown'};
  await invoke('loadOperatingMode');
  assert.equal(controls.operatingModeHostStart.textContent,'확인 필요');
  context.fetch=async()=>({ok:false,json:async()=>({error:'상태를 읽을 수 없습니다.'})});
  await invoke('loadOperatingMode');
  assert.equal(controls.operatingModeHostStart.textContent,'확인 실패');
  assert.equal(controls.operatingModeMessage.textContent,'상태를 읽을 수 없습니다.');
  assert.equal(controls.operatingModeOpen.disabled,true);
  console.log('PASS operating mode navigation, scoped status, refresh, launch intent, busy, missing and error states');
}
check().catch(error=>{console.error(error);process.exitCode=1;});
