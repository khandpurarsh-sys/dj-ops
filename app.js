import {setup,unlock,decryptPayload,kid} from './crypto.js';
const $=s=>document.querySelector(s),root=$('#root');
const inr=n=>'₹'+Number(n).toLocaleString('en-IN');
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const LS=localStorage;let priv=null,myKid=null,data=null,tab='today',q='',ch='All',status='';
const shell=inner=>`<div class="app"><div class="blob b1"></div><div class="blob b2"></div><div class="blob b3"></div>${inner}</div>`;
const logo='<img class="logo" src="icon-192.png" alt="Dressjet">';
function lockScreen(){const v=JSON.parse(LS.getItem('dj_vault')||'null');
 root.innerHTML=shell(`<div class="lock">${logo}<h1>Dressjet Ops</h1>${v?`<p>Enter your passphrase to open.</p><div class="glass"><input id="pw" type="password" autocomplete="current-password" placeholder="Passphrase"><button class="btn" id="go">Unlock</button><div class="err" id="err"></div></div>`:
 `<p>First time on this phone. Choose a passphrase. It never leaves this phone and cannot be recovered, so keep it somewhere safe.</p><div class="glass"><input id="pw" type="password" placeholder="Passphrase (10+ characters)"><input id="pw2" type="password" placeholder="Repeat passphrase"><button class="btn" id="go">Create</button><div class="err" id="err"></div></div>`}</div>`);
 $('#go').onclick=async()=>{const e=$('#err');e.textContent='';const pw=$('#pw').value;
  try{ if(v){priv=await unlock(v,pw);myKid=await kid(v.pub);start();}
   else{ if(pw.length<10){e.textContent='Use at least 10 characters.';return;} if(pw!==$('#pw2').value){e.textContent='Passphrases do not match.';return;}
    $('#go').textContent='Working...';const r=await setup(pw);LS.setItem('dj_vault',JSON.stringify(r.vault));showKey(r.pubText);} }
  catch(x){e.textContent=v?'Wrong passphrase.':'Something went wrong: '+x.message;$('#go').textContent=v?'Unlock':'Create';}};}
function showKey(t){root.innerHTML=shell(`<div class="lock">${logo}<h1>Almost done</h1><p>Send this public key to your assistant. It is not secret. It lets updates be locked so only this phone can read them.</p><div class="glass"><div class="keybox" id="k">${esc(t)}</div><button class="btn" id="cp">Copy key</button><button class="btn alt" id="sh">Share key</button><button class="btn alt" id="nx">Continue</button></div></div>`);
 $('#cp').onclick=async()=>{try{await navigator.clipboard.writeText(t);$('#cp').textContent='Copied'}catch{}};
 $('#sh').onclick=()=>navigator.share?navigator.share({text:t}):0;$('#nx').onclick=lockScreen;}
async function fetchLatest(){const repo=(window.DJ_CONFIG||{}).repo;
 const r=await fetch(`https://api.github.com/repos/${repo}/issues/comments?sort=created&direction=desc&per_page=1&_=${Date.now()}`,{cache:'no-store',headers:{Accept:'application/vnd.github+json'}});
 if(!r.ok)throw new Error('GitHub '+r.status);const j=await r.json();if(!j.length)throw new Error('No data yet');
 const body=j[0].body.trim().replace(/^```(json)?/,'').replace(/```$/,'').trim();LS.setItem('dj_last',body);return body;}
async function load(){try{status='Updating...';render();let b;try{b=await fetchLatest();status='';}catch(e){b=LS.getItem('dj_last');status=b?'Offline, showing last saved data':'No data yet: '+e.message;if(!b){render();return;}}
 data=await decryptPayload(JSON.parse(b),priv,myKid);}catch(e){status='Could not read update: '+e.message;}render();}
function render(){if(!data){root.innerHTML=shell(`<header>${logo}<div><h1>Dressjet Ops</h1><p>${esc(status)}</p></div><button class="refresh" id="rf">Refresh</button></header>`);$('#rf').onclick=load;return;}
 const s=data.snapshot,orders=data.orders,live=orders.filter(o=>o.status!=='Cancelled');
 let h=`<header>${logo}<div><h1>${tab==='today'?'Today':'Orders'}</h1><p>Dressjet · ${esc(s.at)}${status?' · '+esc(status):''}</p></div><button class="refresh" id="rf">Refresh</button></header><main>`;
 if(tab==='today'){const m={};live.forEach(o=>{(m[o.ch]=m[o.ch]||{n:0,amt:0});m[o.ch].n++;m[o.ch].amt+=o.amt});const by=Object.entries(m).sort((a,b)=>b[1].amt-a[1].amt),max=Math.max(1,...by.map(c=>c[1].amt));
  h+=`<section class="glass hero"><span class="eyebrow">Today's revenue</span><div class="big">${inr(s.revenue)}</div><div class="sub"><span class="chip">so far</span> Yesterday full day: ${inr(s.revenuePrev)}</div><div class="split"><div><b>${s.items}</b><span>order items</span></div><div><b>${orders.length}</b><span>orders</span></div><div><b>${inr(Math.round(s.revenue/Math.max(1,live.length)))}</b><span>avg order</span></div></div></section>
  <h2>Needs attention</h2><div class="grid2">${s.alerts.map(a=>`<div class="glass tile ${a.tone}"><b>${a.v}</b><span>${esc(a.k)}</span></div>`).join('')}</div>
  <h2>Channels today</h2><section class="glass list">${by.map(([c,v])=>`<div class="chrow"><div class="chtop"><span>${esc(c)}</span><span>${inr(v.amt)} · ${v.n}</span></div><div class="bar"><i style="width:${v.amt/max*100}%"></i></div></div>`).join('')}</section>
  <h2>Pending today</h2><section class="glass list">${s.pipeline.map(p=>`<div class="line"><span>${esc(p.k)}</span><b>${p.v}</b></div>`).join('')}</section>
  <h2>Catalog sync</h2><section class="glass list">${s.sync.map(p=>`<div class="line"><span>${esc(p.k)}</span><b>${p.v}</b></div>`).join('')}<div class="line"><span>Channel listings</span><b>${Number(s.listings).toLocaleString('en-IN')}</b></div></section>`;}
 else{const chans=['All',...new Set(orders.map(o=>o.ch))];const list=orders.filter(o=>(ch==='All'||o.ch===ch)&&(!q||(o.id+o.items.map(i=>i.sku).join(' ')).toLowerCase().includes(q.toLowerCase())));
  h+=`<div class="glass search"><input id="q" placeholder="Search order or SKU" value="${esc(q)}"></div><div class="pills">${chans.map(c=>`<button data-c="${esc(c)}" class="${c===ch?'on':''}">${esc(c)}</button>`).join('')}</div><section class="ol">${list.length?list.map(o=>`<article class="glass order"><div class="otop"><b>${esc(o.id)}</b><span class="st ${o.status.toLowerCase()}">${esc(o.status)}</span></div><div class="osku">${o.items.map(i=>esc(i.sku)+(i.qty>1?' ×'+i.qty:'')).join(', ')}</div><div class="ometa"><span>${esc(o.ch)} · ${esc(o.pay)} · ${esc(o.time)}</span><b>${o.amt?inr(o.amt):'—'}</b></div></article>`).join(''):'<div class="glass empty">No orders match.</div>'}</section>`;}
 h+=`</main><nav class="glass tabbar"><button data-t="today" class="${tab==='today'?'on':''}">Today</button><button data-t="orders" class="${tab==='orders'?'on':''}">Orders</button></nav>`;
 root.innerHTML=shell(h);$('#rf').onclick=load;document.querySelectorAll('[data-t]').forEach(b=>b.onclick=()=>{tab=b.dataset.t;render()});document.querySelectorAll('[data-c]').forEach(b=>b.onclick=()=>{ch=b.dataset.c;render()});
 const qi=$('#q');if(qi)qi.oninput=e=>{q=e.target.value;const p=e.target.selectionStart;render();const n=$('#q');n.focus();n.setSelectionRange(p,p)};}
let timer;function start(){load();clearInterval(timer);timer=setInterval(()=>{if(!document.hidden)load()},((window.DJ_CONFIG||{}).pollMinutes||5)*60000);}
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&priv)load()});
if('serviceWorker'in navigator)navigator.serviceWorker.register('sw.js');
lockScreen();
