#!/usr/bin/env node
'use strict';
// Static DOM/timer harness for the exact PC inline log functions. No live server.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

(async () => {
  const root = path.resolve(__dirname, '../../');
  const html = fs.readFileSync(path.join(root, 'GSC/ServerCenter/cmd/client/dashboard.html'), 'utf8');
  const match = html.match(/<script>([\s\S]*?)<\/script>/i);
  assert.ok(match, 'missing inline dashboard JavaScript');
  const body = match[1];
  const start = body.indexOf('let consoleLogTimer=');
  const end = body.indexOf('async function sendCmd()', start);
  assert.ok(start > 0 && end > start, 'missing bounded log refresh implementation');
  const code = body.slice(start, end);
  const timers = new Map();
  let nextTimerId = 1, calls = 0;
  const listeners = {};
  const log = {textContent:'',dataset:{},scrollTop:0,clientHeight:100,scrollHeight:500};
  const server = {value:'wild'}, kind = {value:'server'};
  const elements = {log,consoleServer:server,logKind:kind};
  const document = {
    visibilityState:'visible',
    addEventListener(name, cb){listeners[name]=cb}
  };
  const ctx = {
    console,
    document,
    currentView:'dashboard',
    $: id => elements[id],
    setInterval(fn,ms) { assert.equal(ms,4000); const id=nextTimerId++;timers.set(id,fn);return id },
    clearInterval(id){timers.delete(id)},
    fetch: async url => {
      calls++;
      assert.ok(url.startsWith('/api/log?'), 'wrong endpoint');
      return {ok:true,text:async()=> 'log-'+calls+'\n'};
    }
  };
  vm.createContext(ctx);
  vm.runInContext(code,ctx);
  vm.runInContext('syncConsoleLogPolling()',ctx);
  assert.equal(timers.size,0,'no polling outside console');
  vm.runInContext("currentView='console';syncConsoleLogPolling()",ctx);
  assert.equal(timers.size,1,'one timer on visible console');
  const tick=[...timers.values()][0];
  await tick();
  assert.equal(calls,1,'automatic fetch while open');
  assert.equal(log.textContent,'log-1\n');
  assert.equal(log.scrollTop,500,'follow tail on first load');
  log.scrollTop=20;log.scrollHeight=500;
  await vm.runInContext('loadLog()',ctx);
  assert.equal(log.scrollTop,20,'scroll position retained when reading history');
  document.visibilityState='hidden';listeners.visibilitychange();
  assert.equal(timers.size,0,'hidden tab polling stopped');
  document.visibilityState='visible';listeners.visibilitychange();
  assert.equal(timers.size,1,'visible console polling resumed');
  vm.runInContext('toggleConsoleAutoRefresh(false)',ctx);
  assert.equal(timers.size,0,'manual disable honored');
  vm.runInContext("currentView='servers';syncConsoleLogPolling()",ctx);
  assert.equal(timers.size,0,'inactive console polling stopped');
  const dart = fs.readFileSync(path.join(root, 'GSCM/lib/screens/server_detail_screen.dart'),'utf8');
  assert.match(dart,/bool autoRefresh = true;/);
  assert.match(dart,/Timer\.periodic\(const Duration\(seconds: 4\)/);
  assert.match(dart,/_startAutoRefresh\(\);/);
  assert.match(dart,/_logInFlight/);
  assert.match(dart,/unawaited\(_load\(silent: true\)\)/);
  assert.match(html,/id="consoleAutoRefresh" type="checkbox" checked/);
  console.log('PASS: PC visible-only polling, hidden/disable behavior, scroll preservation; GSCM auto default');
})().catch(e=>{console.error(e);process.exitCode=1});
