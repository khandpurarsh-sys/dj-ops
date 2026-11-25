// feed-v2 loader gates (ios-app, module form). Run: node test/feed-v2.test.mjs (no deps, Node 22+)
// Exercises the real feed-v2-loader.mjs and the unchanged crypto.js. Only the policy kid list and the
// in-memory store are test doubles. No network, no real keys.
import {readFileSync} from 'node:fs';
import {webcrypto as wc, createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {PROPOSED_POLICY,createV2Loader,validateFeed,resolveEndpoint,utf8,sha256} from '../feed-v2-loader.mjs';
import {setup,unlock,kid,decryptPayload} from '../crypto.js';

const BASE='https://khandpurarsh-sys.github.io/dj-ops/';
const REPO='khandpurarsh-sys/dj-ops',POLV='dressjet-static-v2-proposed-1';
const b64=u=>Buffer.from(u).toString('base64'),H=x=>createHash('sha256').update(x).digest('hex');
const PASS='test-pass-123',vA=await setup(PASS),vB=await setup(PASS);
const privA=await unlock(vA.vault,PASS),kidA=await kid(vA.vault.pub),kidB=await kid(vB.vault.pub);
// policy: swap one non-removable required kid for the test phone's kid
const REQ=PROPOSED_POLICY.requiredKids.map(k=>k==='zsExOo1d'?kidA:k);
const NON_REMOVABLE=REQ.filter(k=>!['eKlKbhWk','xZw9PRCY','NczC6Ww8','yKOhpUFs','gejFeX4x','BdzJ1fS2'].includes(k));
const ALLKIDS=NON_REMOVABLE.slice().sort();
const mk=(over={})=>({...PROPOSED_POLICY,requiredKids:REQ,...over});
const fakeMsg=k=>({kid:k,epk:{x:'x',y:'y'},iv:'iv',wk:'wk'});

async function env(data,{sid,slim=false,extra={},kids=ALLKIDS,rawBytes=null}){
 const raw=rawBytes||new TextEncoder().encode(JSON.stringify(data)),zraw=gzipSync(raw);
 const dk=wc.getRandomValues(new Uint8Array(32)),div=wc.getRandomValues(new Uint8Array(12));
 const dkey=await wc.subtle.importKey('raw',dk,'AES-GCM',false,['encrypt']);
 const dct=await wc.subtle.encrypt({name:'AES-GCM',iv:div},dkey,zraw);
 const eph=await wc.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
 const rpk=await wc.subtle.importKey('jwk',{kty:'EC',crv:'P-256',x:vA.vault.pub.x,y:vA.vault.pub.y},{name:'ECDH',namedCurve:'P-256'},false,[]);
 const bits=await wc.subtle.deriveBits({name:'ECDH',public:rpk},eph.privateKey,256);
 const hk=await wc.subtle.importKey('raw',bits,'HKDF',false,['deriveKey']);
 const key=await wc.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:new Uint8Array(0),info:new TextEncoder().encode('djops-v1')},hk,{name:'AES-GCM',length:256},false,['encrypt']);
 const iv=wc.getRandomValues(new Uint8Array(12)),wk=await wc.subtle.encrypt({name:'AES-GCM',iv},key,dk),e=await wc.subtle.exportKey('jwk',eph.publicKey);
 const msgs=kids.map(k=>k===kidA?{kid:k,epk:{x:e.x,y:e.y},iv:b64(iv),wk:b64(wk)}:fakeMsg(k));
 return JSON.stringify({v:2,z:1,iv:b64(div),ct:b64(dct),msgs,sid,...(slim?{slim:1}:{}),...extra});
}
const ISO='2026-11-25T10:00:00Z';
const AUX=await env({kind:'x'},{sid:'aux',slim:true}); // fixed aux body so unchanged aux rows keep their hash across generations
async function buildFeed({gen=1,prev=null,sid='SID-1',payload,mut=null,slimKids,fullKids}={}){
 payload=payload||{snapshot:{revenue:1,at:ISO}};
 const slim=await env(payload,{sid,slim:true,kids:slimKids||ALLKIDS}),full=await env(payload,{sid,kids:fullKids||ALLKIDS});
 const aux=AUX;
 const row=(body,source)=>({body,byteLength:utf8(body).length,sha256:H(body),publishedAt:ISO,source});
 const f={version:2,repo:REPO,generation:gen,previous:prev,policyVersion:POLV,mode:'static-primary',publishedAt:ISO,sid,rows:{
  '1':row(slim,{kind:'static',generation:gen}),'3':row(full,{kind:'static',generation:gen}),
  '2':row(aux,{kind:'github-comment',commentId:11,owner:'khandpurarsh-sys'}),'87':row(aux,{kind:'github-comment',commentId:12,owner:'khandpurarsh-sys'}),'88':row(aux,{kind:'github-comment',commentId:13,owner:'khandpurarsh-sys'})}};
 if(mut)mut(f);return f;
}
const res=(bytes,{status=200,headers={},url,redirected=false}={})=>({ok:status===200,status,redirected,url,headers:{get:k=>headers[k.toLowerCase()]??null},
 body:status!==200?null:{getReader:()=>{let o=0;return{read:async()=>{if(o>=bytes.length)return{done:true};const c=bytes.slice(o,o+65536);o+=c.length;return{done:false,value:c}},cancel:async()=>{}}}}});
function net(map,log){return async(url,opts)=>{log&&log.push({url,opts});const v=map[url];if(v===undefined)return res(new Uint8Array(),{status:404,url});if(typeof v==='function')return v(url,opts);return res(typeof v==='string'?utf8(v):v,{url});};}
function memStore(){let rec=null;return{get rec(){return rec},set rec(v){rec=v},async read(){return rec},async commit(r){if(rec&&(rec.generation>r.generation||(rec.generation===r.generation&&rec.feedSha256!==r.feedSha256)))throw Error('Static v2: concurrent acceptance conflict');rec=r}}}
const decrypt=(e,max)=>decryptPayload(e,privA,kidA,{maxPlaintextBytes:max});
const FEEDURL=BASE+'feed-v2.json';
async function loader(feed,{policy,store=memStore(),fetcher,location=BASE,extra={}}={}){
 const text=typeof feed==='string'?feed:JSON.stringify(feed);
 if(!policy){const j=JSON.parse(text);policy=mk({bootstrapGeneration:j.generation,bootstrapSha256:H(text)});}
 return{store,loader:createV2Loader({policy,store,fetcher:fetcher||net({[FEEDURL]:text,...extra}),location,decrypt}),text,policy};
}
let pass=0,fail=0;
const t=(n,ok)=>{if(ok){pass++;console.log('ok:',n)}else{fail++;console.log('FAIL:',n)}};
const throws=async(n,fn,re)=>{try{await fn();fail++;console.log('FAIL (no throw):',n)}catch(e){if(re.test(e.message)){pass++;console.log('ok:',n)}else{fail++;console.log('FAIL ('+e.message+'):',n)}}};

// ---- plain (non-archive) feed ----
let f=await buildFeed(),L=await loader(f),r=await L.loader.load();
t('genesis accepted and decrypted',r.data.snapshot.revenue===1&&r.record.generation===1&&!r.stale&&L.store.rec.generation===1);
r=await L.loader.load();t('same generation same bytes idempotent',r.record.generation===1&&!r.stale);
// replay / ancestry
const g1=f,g1t=JSON.stringify(g1);
let g2=await buildFeed({gen:2,prev:{generation:1,sha256:H(g1t)}});
L=await loader(g1);await L.loader.load();
const t2=JSON.stringify(g2),pol2=mk({bootstrapGeneration:1,bootstrapSha256:H(g1t)});
const swap=(L,text)=>createV2Loader({policy:pol2,store:L.store,fetcher:net({[FEEDURL]:text}),location:BASE,decrypt});
r=await swap(L,t2).load();t('gen2 object previous accepted',r.record.generation===2&&!r.stale);
let g2bad=await buildFeed({gen:2,prev:{generation:1,sha256:'f'.repeat(64)}});
L=await loader(g1);await L.loader.load();
r=await swap(L,JSON.stringify(g2bad)).load();
t('object previous wrong sha rejected, last-good served stale',r.stale&&r.record.generation===1&&/previous hash mismatch/.test(r.status));
let g2gen=await buildFeed({gen:2,prev:{generation:5,sha256:'f'.repeat(64)}});
r=await swap(L,JSON.stringify(g2gen)).load();t('object previous generation mismatch rejected',r.stale&&/ancestry/.test(r.status));
let g2str=await buildFeed({gen:2,prev:H(g1t)});
r=await swap(L,JSON.stringify(g2str)).load();t('string previous (legacy shape) is NOT accepted by the module (exact object required)',r.stale&&/ancestry/.test(r.status));
// skipped generations: allowed by the reference (previous only has to be {generation: gen-1, sha256}; the hash is compared to the saved acceptance only when gen === saved+1)
{const st=memStore(),L1=await loader(g1,{store:st});await L1.loader.load();
 const g4=await buildFeed({gen:4,prev:{generation:3,sha256:'c'.repeat(64)}});
 const rr=await createV2Loader({policy:pol2,store:st,fetcher:net({[FEEDURL]:JSON.stringify(g4)}),location:BASE,decrypt}).load();
 t('skipped generation (saved 1 -> 4, unverifiable previous hash) accepted by reference rules',!rr.stale&&rr.record.generation===4&&st.rec.generation===4);
 const g4b=await buildFeed({gen:4,prev:{generation:2,sha256:'c'.repeat(64)}});const st2=memStore(),L2=await loader(g1,{store:st2});await L2.loader.load();
 const r2=await createV2Loader({policy:pol2,store:st2,fetcher:net({[FEEDURL]:JSON.stringify(g4b)}),location:BASE,decrypt}).load();
 t('skip with previous.generation != gen-1 rejected',r2.stale&&/ancestry/.test(r2.status))}
// rollback / conflict
L=await loader(g2);await L.loader.load();
r=await createV2Loader({policy:mk({bootstrapGeneration:1,bootstrapSha256:H(g1t)}),store:L.store,fetcher:net({[FEEDURL]:g1t}),location:BASE,decrypt}).load();
t('older generation rejected, last-good served stale',r.stale&&/rollback/.test(r.status)&&r.record.generation===2);
let g2c=await buildFeed({gen:2,prev:{generation:1,sha256:H(g1t)},sid:'SID-X'});
r=await createV2Loader({policy:pol2,store:L.store,fetcher:net({[FEEDURL]:JSON.stringify(g2c)}),location:BASE,decrypt}).load();
t('same generation different bytes rejected',r.stale&&/conflict/.test(r.status));
// structure
const bad=async(n,mut,re)=>{const x=await buildFeed({mut});const Lx=await loader(x);await throws(n,()=>Lx.loader.load(),re)};
await bad('wrong repo rejected',x=>{x.repo='evil/repo'},/format/);
await bad('missing row rejected',x=>{delete x.rows['88']},/format/);
await bad('extra row rejected',x=>{x.rows['9']={...x.rows['1']}},/format/);
await bad('hash mismatch rejected',x=>{x.rows['1'].sha256='0'.repeat(64)},/row hash/);
await bad('byteLength mismatch rejected',x=>{x.rows['1'].byteLength++},/row hash/);
await bad('wrong policyVersion rejected',x=>{x.policyVersion='dressjet-static-v2-proposed-2'},/format/);
await bad('missing policyVersion rejected',x=>{delete x.policyVersion},/format/);
await bad('genesis with previous rejected',x=>{x.previous={generation:0,sha256:'a'.repeat(64)}},/genesis/);
await bad('sid mismatch rejected',x=>{x.sid='OTHER'},/snapshots mismatch/);
await bad('legacy commentId on row rejected',x=>{x.rows['2'].commentId=5},/legacy commentId/);
{const Lx=await loader('{not json',{policy:mk({bootstrapGeneration:1,bootstrapSha256:'a'.repeat(64)})});await throws('malformed rejected',()=>Lx.loader.load(),/JSON/)}
// roster
{const x=await buildFeed({slimKids:ALLKIDS.filter(k=>k!==ALLKIDS[0]),fullKids:ALLKIDS.filter(k=>k!==ALLKIDS[0])});const Lx=await loader(x);await throws('missing required recipient rejected',()=>Lx.loader.load(),/recipient set/)}
{const x=await buildFeed({slimKids:[...ALLKIDS,'EVILKID1'],fullKids:[...ALLKIDS,'EVILKID1']});const Lx=await loader(x);await throws('unapproved extra recipient rejected',()=>Lx.loader.load(),/recipient set/)}
// decrypt failure does not pin
{const x=await buildFeed();const st=memStore();const Lx=await loader(x,{store:st});const wrong=createV2Loader({policy:Lx.policy,store:st,fetcher:net({[FEEDURL]:Lx.text}),location:BASE,decrypt:(e,m)=>decryptPayload(e,privA,kidB,{maxPlaintextBytes:m})});
 await throws('undecryptable rejected',()=>wrong.load(),/not encrypted for this phone/);t('nothing pinned on decrypt failure',st.rec===null)}
// size / HTTP / redirect / headers
{const big=JSON.stringify(f).slice(0,-1)+',"pad":"'+' '.repeat(2*1024*1024)+'"}';const Lx=await loader(f);
 const lx=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:big}),location:BASE,decrypt});await throws('oversized response rejected',()=>lx.load(),/response limit/);
 const l2=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({}),location:BASE,decrypt});await throws('404 with no cache surfaces',()=>l2.load(),/HTTP 404/);
 const l3=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:(u)=>res(utf8(Lx.text),{url:u,redirected:true})}),location:BASE,decrypt});await throws('redirect rejected',()=>l3.load(),/redirect/);
 const l4=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:(u)=>res(utf8(Lx.text),{url:u,headers:{'content-length':'99999999'}})}),location:BASE,decrypt});await throws('declared length over limit rejected',()=>l4.load(),/response length/);}
// fetch options + no API fallback: only the pinned feed URL is ever requested
{const log=[],Lx=await loader(f,{fetcher:null});const lg=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:Lx.text},log),location:BASE,decrypt});await lg.load();
 t('fetch uses redirect:error, credentials omit, no-store',log.length===1&&log[0].opts.redirect==='error'&&log[0].opts.credentials==='omit'&&log[0].opts.cache==='no-store');
 const log2=[];const l2=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({},log2),location:BASE,decrypt});try{await l2.load()}catch{}
 t('failure never touches api.github.com',log2.length===1&&log2.every(x=>x.url.startsWith(BASE)))}
// stale banner keeps last good
{const st=memStore(),Lx=await loader(f,{store:st});await Lx.loader.load();
 const lf=createV2Loader({policy:Lx.policy,store:st,fetcher:net({}),location:BASE,decrypt});const rr=await lf.load();
 t('any v2 failure keeps last-saved data with stale banner',rr.stale&&rr.data.snapshot.revenue===1&&/Showing last saved data/.test(rr.status))}
// location pinning (feedBase-as-location), fail closed BEFORE any fetch
for(const [n,loc] of [['native WebView origin',"capacitor://localhost/"],['wrong host','https://evil.example/dj-ops/'],['http scheme','http://khandpurarsh-sys.github.io/dj-ops/'],['wrong path prefix','https://khandpurarsh-sys.github.io/other/'],['empty feedBase','']]){
 const log=[],Lx=await loader(f,{fetcher:null});const lx=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:Lx.text},log),location:loc,decrypt});
 await throws('location rejected before fetch: '+n,()=>lx.load(),/.+/);t('no request made for '+n,log.length===0);}
t('resolveEndpoint pinned to /dj-ops/feed-v2.json',resolveEndpoint(mk(),BASE)===FEEDURL);

// ---- archive-descriptor feed ----
const sorted=ALLKIDS,EPOCH='roster-'+await sha256(utf8(sorted.join(',')));
async function archive({entries=[[1,2],[3]],gen=1,mut=null,wrapMut=null,chunkMut=null}={}){
 const sid='SID-A',chunks=[],wire={},arrs=entries;let all=[];
 for(const arr of arrs){
  const raw=utf8(JSON.stringify(arr)),ph=H(raw),csid=EPOCH+'-'+ph;
  const wtext=await env({raw:b64(raw)},{sid:csid,extra:{archiveSchema:'djops-retail-archive-v1',archiveEpoch:EPOCH}});
  const wb=utf8(wtext),path='archives/retail-v1/'+H(wtext)+'.json';
  const m={path,wireBytes:wb.length,wireSha256:H(wb),plainBytes:raw.length,plainSha256:ph,entries:arr.length};if(chunkMut)chunkMut(m,wtext);
  chunks.push(m);wire[BASE+path]=wtext;all=all.concat(arr);
 }
 const prefix='{"snapshot":{"at":"'+ISO+'"},"retail":{"priorReadObservations":',suffix='}}';
 const full=prefix+JSON.stringify(all)+suffix,fb=utf8(full);
 const a={schema:'djops-retail-archive-v1',path:'retail.priorReadObservations',generation:gen,sid,epoch:EPOCH,kids:sorted,fullBytes:fb.length,fullSha256:H(fb),entries:all.length,chunks,prefix,suffix};
 if(mut)mut(a);const wrapper={archiveTransport:a};if(wrapMut)wrapMut(wrapper);
 const feed=await buildFeed({gen,sid,payload:wrapper});return{feed,wire,all};
}
{const {feed,wire,all}=await archive(),Lx=await loader(feed,{extra:wire}),rr=await Lx.loader.load();
 t('archive: hydrates exact priorReadObservations from chunks',rr.data.retail.priorReadObservations.length===3&&JSON.stringify(rr.data.retail.priorReadObservations)===JSON.stringify(all)&&!rr.stale);
 t('archive: chunks cached with the accepted record',Object.keys(Lx.store.rec.archiveChunks).length===2);
 // offline: only the cached chunks, no network at all
 const log=[],off=createV2Loader({policy:Lx.policy,store:Lx.store,fetcher:net({},log),location:BASE,decrypt}),ro=await off.load();
 t('archive: offline replay from cached chunks (stale banner, only the feed URL requested)',ro.stale&&ro.data.retail.priorReadObservations.length===3&&log.every(x=>x.url===FEEDURL));
 // cache with a missing chunk fails closed
 const st2=memStore();st2.rec={...Lx.store.rec,archiveChunks:{}};
 await throws('archive: offline cache missing chunk fails closed',()=>createV2Loader({policy:Lx.policy,store:st2,fetcher:net({}),location:BASE,decrypt}).load(),/offline chunk missing|HTTP 404/);
 // chunk requests are only under the validated base
 const log3=[],l3=createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:Lx.text,...wire},log3),location:BASE,decrypt});await l3.load();
 t('archive: chunk URLs all under pinned base',log3.length===3&&log3.every(x=>x.url.startsWith(BASE+'feed-v2.json')||x.url.startsWith(BASE+'archives/retail-v1/')));
 // wire tampering
 const k=Object.keys(wire)[0],tw={...wire,[k]:wire[k].replace(/.$/,' ')};
 await throws('archive: tampered chunk wire rejected',()=>createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:Lx.text,...tw}),location:BASE,decrypt}).load(),/wire integrity/);
 await throws('archive: missing chunk (404) rejected',()=>createV2Loader({policy:Lx.policy,store:memStore(),fetcher:net({[FEEDURL]:Lx.text}),location:BASE,decrypt}).load(),/HTTP 404/);
}
async function archBad(n,opts,re){const {feed,wire}=await archive(opts),Lx=await loader(feed,{extra:wire});await throws(n,()=>Lx.loader.load(),re)}
await archBad('archive: wrong generation rejected',{mut:a=>{a.generation=9}},/lineage/);
await archBad('archive: wrong sid rejected',{mut:a=>{a.sid='nope'}},/lineage/);
await archBad('archive: wrong epoch rejected',{mut:a=>{a.epoch='roster-'+'0'.repeat(64)}},/lineage/);
await archBad('archive: unsorted roster rejected',{mut:a=>{a.kids=a.kids.slice().reverse()}},/lineage/);
await archBad('archive: roster not equal to main recipients rejected',{mut:a=>{a.kids=a.kids.slice(1)}},/lineage/);
await archBad('archive: wrapper with extra keys rejected',{wrapMut:w=>{w.extra=1}},/lineage/);
await archBad('archive: fullSha256 mismatch rejected',{mut:a=>{a.fullSha256='0'.repeat(64)}},/reconstruction hash/);
await archBad('archive: fullBytes mismatch rejected',{mut:a=>{a.fullBytes+=1}},/total count\/length/);
await archBad('archive: entries mismatch rejected',{mut:a=>{a.entries+=1}},/total count\/length|manifest bounds/);
await archBad('archive: fullBytes over 32 MiB rejected',{mut:a=>{a.fullBytes=33554433}},/manifest bounds/);
await archBad('archive: entries over 1024 rejected',{mut:a=>{a.entries=1025}},/manifest bounds/);
await archBad('archive: >64 chunks rejected',{mut:a=>{a.chunks=Array.from({length:65},()=>a.chunks[0])}},/manifest bounds/);
await archBad('archive: chunk path traversal rejected',{chunkMut:m=>{m.path='archives/retail-v1/../feed.json'}},/chunk manifest/);
await archBad('archive: chunk path outside archives dir rejected',{chunkMut:m=>{m.path='evil/'+'a'.repeat(64)+'.json'}},/chunk manifest/);
await archBad('archive: duplicate chunk path rejected',{chunkMut:(m)=>{m.path='archives/retail-v1/'+'a'.repeat(64)+'.json'}},/chunk manifest|wire integrity|HTTP 404/);
await archBad('archive: chunk plainBytes over 1 MiB rejected',{chunkMut:m=>{m.plainBytes=1048577}},/chunk manifest/);
await archBad('archive: chunk wireSha256 wrong rejected',{chunkMut:m=>{m.wireSha256='0'.repeat(64)}},/wire integrity/);
await archBad('archive: chunk entries count wrong rejected',{chunkMut:m=>{m.entries+=1}},/entry count|total count/);
// archive bound while inflating (unchanged crypto.js cap)
{const bomb=gzipSync(Buffer.alloc(9*1024*1024,97)),dk=wc.getRandomValues(new Uint8Array(32));
 const cjs=readFileSync(new URL('../crypto.js',import.meta.url),'utf8');t('crypto.js unchanged 8 MiB inflate cap present',cjs.includes('8388608')&&bomb.length<9*1024*1024);}
// source wiring
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8'),sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
t('app.js uses the module loader with feedBase location',/createV2Loader\(\{policy:PROPOSED_POLICY,store:indexedStore\(window\.indexedDB\),location:\(window\.DJ_CONFIG\|\|\{\}\)\.feedBase/.test(app));
t('app.js has no GitHub API fallback or v1 reader',!/api\.github\.com|staticFeedRead|feedBatch|dj_last|FEEDV2 START/.test(app));
t('app.js decrypt injects live priv/myKid',/decryptPayload\(e,priv,myKid,\{maxPlaintextBytes\}\)/.test(app));
t('sw.js caches loader and keeps feed no-store',sw.includes("'feed-v2-loader.mjs'")&&sw.includes("endsWith('/feed-v2.json')")&&sw.includes('no-store'));
t('package.json prepare-www bundles feed-v2-loader.mjs for the native app',/prepare-www.*cp index\.html app\.js crypto\.js feed-v2-loader\.mjs/.test(readFileSync(new URL('../package.json',import.meta.url),'utf8')));
console.log(fail?fail+' FAILURES ('+pass+' ok)':'ALL PASS ('+pass+')');process.exit(fail?1:0);
