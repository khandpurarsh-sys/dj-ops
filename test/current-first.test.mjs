// current-first loader gates. Run: node test/current-first.test.mjs (Node 22+, no deps).
// Real current-first-loader.mjs; fake decrypt/envelopes and in-memory store are test doubles only.
import {createHash} from 'node:crypto';
import {PROPOSED_POLICY,utf8,sha256} from '../feed-v2-loader.mjs';
import {CF_POLICY,createCurrentFirstLoader,validateRoot} from '../current-first-loader.mjs';
const H=x=>createHash('sha256').update(x).digest('hex'),B=u=>Buffer.from(u).toString('base64');
const KIDS=PROPOSED_POLICY.requiredKids.slice().sort(),EPOCH='roster-'+H(KIDS.join(','));
const BASE='https://khandpurarsh-sys.github.io/dj-ops/',LOC=BASE+'index.html';
const env=(plainObj,sid,extra={})=>JSON.stringify({v:2,z:1,iv:'iv',ct:'ct',sid,msgs:KIDS.map(k=>({kid:k,epk:{x:'x',y:'y'},iv:'iv',wk:'wk'})),__p:plainObj,...extra});
const decrypt=async e=>structuredClone(e.__p);
let pass=0,fails=0;const ok=(c,n)=>{if(c){pass++;console.log('ok  ',n)}else{fails++;console.log('FAIL',n)}};
const rejects=async(f,re,n)=>{try{await f();ok(false,n+' (no error)')}catch(e){ok(re.test(e.message),n+' ['+e.message+']')}};

// full candidate: history rows with deferred detail (billList present on every row, like the real feed)
const mkFull=()=>({snapshot:{at:'x'},retail:{},history:[{d:'2026-11-26',rev:10,billList:[{id:1}]},{d:'2026-11-27',rev:20,billList:[{id:2}]},{d:'2026-11-28',rev:30,billList:[{id:3}]}],retailHistory:[{d:'2026-11-27',rev:5,billList:[]}]});
const ONLINE_DEFER=['billList','cancelledOrders','finalOrders','postCloseCurrentObservation'],RETAIL_DEFER=['billList','itemOnlyExchanges','unmatchedItemRows','zeroNet179Only','missingItemAmounts'];
const strip=(r,defer)=>{const s={...r};for(const k of defer)delete s[k];return s};
function fixture({gen=7,sid='SID',prev={generation:6,sha256:'a'.repeat(64)},tamper=null,fullMutate=null,gap=false}={}){
 const full=mkFull();const projSource=fullMutate?structuredClone(full):full;if(fullMutate)fullMutate(full);const raw=utf8(JSON.stringify(full)),cut=[0,Math.floor(raw.length/3),Math.floor(raw.length*2/3),raw.length];
 const chunks={},descs=[];
 for(let i=0;i<3;i++){
  const part=raw.slice(cut[i],cut[i+1]),f={schema:'djops-full-fragment-v1',raw:B(part)},pj=utf8(JSON.stringify(f));
  const rawSha=H(part),wire=env(f,'full-'+rawSha,{archiveEpoch:EPOCH,archiveSchema:'djops-full-background-v1'}),wb=utf8(wire),path='archives/current-first-v1/'+H(wb)+'.json';
  chunks[path]=wire;descs.push({path,wireBytes:wb.length,wireSha256:H(wb),plainBytes:pj.length,plainSha256:H(pj),offset:cut[i]+(gap&&i===2?1:0),rawBytes:part.length,rawSha256:rawSha});
 }
 const dayIx=(r,i,defer)=>({ordinal:i,day:r.d,summary:strip(r,defer),deferredMembers:defer.filter(k=>k in r),detailIncluded:i>=1});
 const hi={schema:'djops-history-index-v1',detailMode:'automatic-background',
  onlineDays:projSource.history.map((r,i)=>dayIx(r,i,ONLINE_DEFER)),
  retailDays:projSource.retailHistory.map((r,i)=>({ordinal:i,day:r.d,summary:strip(r,RETAIL_DEFER),deferredMembers:RETAIL_DEFER.filter(k=>k in r),detailIncluded:true}))};
 const cur={schema:'djops-current-projection-v1',generation:gen,sid,reportingDay:'2026-11-28',sourceDays:{today:'2026-11-28',yesterday:'2026-11-27'},
  data:{snapshot:projSource.snapshot,retail:projSource.retail,history:projSource.history.slice(1),retailHistory:projSource.retailHistory.slice()},
  historyIndex:hi,background:{schema:'djops-full-background-v1',format:'concatenate-raw-chunks-v1',fullBytes:raw.length,fullSha256:H(raw),chunks:descs}};
 if(tamper)tamper(cur,chunks);
 const body=env(cur,sid),bb=utf8(body),aux={};
 for(const n of ['2','87','88']){const ab=env({n},'aux'+n);aux[n]={body:ab,byteLength:utf8(ab).length,sha256:H(utf8(ab)),publishedAt:'2026-11-28T06:00:00Z',source:{kind:'github-comment',commentId:100+Number(n),owner:'khandpurarsh-sys'}};}
 const root={schema:'djops-current-first-v1',repo:'khandpurarsh-sys/dj-ops',policyVersion:'djops-current-first-policy-1',generation:gen,previous:prev,sid,publishedAt:'2026-11-28T06:00:00Z',sourceV2:{generation:842,sha256:'b'.repeat(64)},current:{body,byteLength:bb.length,sha256:H(bb)},aux};
 return{rootBytes:utf8(JSON.stringify(root)),chunks,full};
}
const mem=()=>{let acc=null,ch={};return{async read(){return acc},async commit(r){if(acc&&(acc.generation>r.generation||(acc.generation===r.generation&&acc.rootSha256!==r.rootSha256)))throw Error('conflict');acc=r},async readChunks(){return ch},async putChunks(m){Object.assign(ch,m)},get acc(){return acc}}};
const mkFetch=(fx,fail=new Set())=>async url=>{const rel=url.replace(BASE,'');let body;
 if(rel==='feed-current-v1.json')body=fx.rootBytes;else if(fx.chunks[rel]!==undefined&&!fail.has(rel))body=utf8(fx.chunks[rel]);else return{ok:false,status:404,headers:new Headers(),url,redirected:false};
 return{ok:true,status:200,url,redirected:false,headers:new Headers({'content-length':String(body.length)}),body:{getReader(){let d=false;return{read:async()=>d?{done:true}:(d=true,{done:false,value:body}),cancel:async()=>{}}}}};};
const policyFor=fx=>({...CF_POLICY,enabled:true,bootstrapGeneration:7,bootstrapSha256:H(fx.rootBytes),requiredKids:KIDS});
const wait=ms=>new Promise(r=>setTimeout(r,ms));

{ // happy path
 const fx=fixture(),store=mem(),got=[];let ready=null;
 const L=createCurrentFirstLoader({policy:policyFor(fx),store,fetcher:mkFetch(fx),location:LOC,decrypt});
 const cur=await L.loadCurrent({onHistoryReady:r=>{ready=r}});
 ok(cur.historyReady===false&&cur.historyState==='loading'&&cur.stale===false,'loadCurrent resolves fresh with loading state');
 ok(store.acc?.generation===7&&store.acc.full===null&&typeof store.acc.raw==='string','high-water + verified root wire state committed before return, no full yet');
 ok(cur.historyIndex.onlineDays.length===3&&!('billList' in cur.historyIndex.onlineDays[0].summary),'index summaries carry no deferred members');
 await wait(50);
 ok(ready?.historyReady===true&&ready.historyState==='ready'&&JSON.stringify(ready.data)===JSON.stringify(fx.full),'onHistoryReady delivers exact full original');
 ok(store.acc.full?.sha256===H(utf8(JSON.stringify(fx.full))),'full acceptance recorded');
}
{ // chunk tampering: wire hash mismatch -> error state, no full commit, current still valid
 const fx=fixture(),store=mem();let err=null,ready=false;const paths=Object.keys(fx.chunks);fx.chunks[paths[1]]=fx.chunks[paths[1]].replace('"ct"','"cx"');
 const L=createCurrentFirstLoader({policy:policyFor(fx),store,fetcher:mkFetch(fx),location:LOC,decrypt});
 await L.loadCurrent({onHistoryReady:()=>{ready=true},onHistoryError:e=>{err=e}});await wait(50);
 ok(!ready&&err?.historyState==='error'&&/integrity/.test(err.reason)&&store.acc.full===null&&L.historyState()==='error','tampered chunk => error, no full acceptance');
}
{ // missing chunk then retry succeeds
 const fx=fixture(),store=mem(),down=new Set([Object.keys(fx.chunks)[2]]);let err=null,ready=null;
 const L=createCurrentFirstLoader({policy:policyFor(fx),store,fetcher:mkFetch(fx,down),location:LOC,decrypt});
 await L.loadCurrent({onHistoryReady:r=>{ready=r},onHistoryError:e=>{err=e}});await wait(50);
 ok(err&&!ready,'network failure on a chunk => retryable error');
 down.clear();ok(L.retryHistory()===true,'retry accepted');await wait(50);ok(ready?.historyReady===true,'retry reaches ready');
}
{ // full candidate inconsistent with current/index -> hydration rejects, current unchanged
 const cases=[
  [/index summary vs full row/,f=>{f.history[0].rev=11},'full row disagrees with index summary'],
  [/projection detail row vs full/,f=>{f.history[1].billList=[{id:99}]},'today/yesterday detail row changed in full'],
  [/deferred member list vs full row/,f=>{delete f.history[0].billList},'deferred member list disagrees with full row'],
  [/projection value differs from full/,f=>{f.snapshot.at='y'},'shown snapshot value changed in full'],
 ];
 for(const [re,mut,name] of cases){
  const fx=fixture({fullMutate:mut}),store=mem();let err=null,ready=false;
  const L=createCurrentFirstLoader({policy:policyFor(fx),store,fetcher:mkFetch(fx),location:LOC,decrypt});
  const cur=await L.loadCurrent({onHistoryReady:()=>{ready=true},onHistoryError:e=>{err=e}});await wait(50);
  ok(!ready&&err&&re.test(err.reason)&&store.acc.full===null&&cur.stale===false,'inconsistency rejected: '+name+' ['+(err&&err.reason)+']');
 }
}
{ // contract violations rejected
 await rejects(async()=>{const fx=fixture({gap:true});await createCurrentFirstLoader({policy:policyFor(fx),store:mem(),fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent()},/contiguous/,'non-contiguous chunks rejected');
 await rejects(async()=>{const fx=fixture({tamper:c=>{c.historyIndex.onlineDays[0].summary.billList=[]}});await createCurrentFirstLoader({policy:policyFor(fx),store:mem(),fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent()},/deferred member/,'index summary with deferred member rejected');
 await rejects(async()=>{const fx=fixture({tamper:c=>{c.background.chunks[0].path='archives/retail-v1/'+'0'.repeat(64)+'.json'}});await createCurrentFirstLoader({policy:policyFor(fx),store:mem(),fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent()},/descriptor/,'v2 archive path alias rejected');
 await rejects(async()=>{const fx=fixture({tamper:c=>{c.sid='OTHER'}});await createCurrentFirstLoader({policy:policyFor(fx),store:mem(),fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent()},/projection format/,'projection sid mismatch rejected');
 await rejects(async()=>{const fx=fixture();await createCurrentFirstLoader({policy:{...policyFor(fx),enabled:false},store:mem(),fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent()},/disabled/,'disabled policy blocks');
}
{ // offline fallback: saved verified figures shown stale with original source times
 const fx=fixture(),store=mem();const p=policyFor(fx);
 await createCurrentFirstLoader({policy:p,store,fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent();await wait(50);
 const down=async()=>{throw Error('offline')};
 let ready=null,err=null;
 const r=await createCurrentFirstLoader({policy:p,store,fetcher:down,location:LOC,decrypt}).loadCurrent({onHistoryReady:x=>{ready=x},onHistoryError:e=>{err=e}});
 ok(r.stale===true&&/original source times/.test(r.status)&&r.data&&r.data.history.length===2,'offline: last saved figures returned stale, labelled with original source times');
 await wait(50);
 ok(ready?.historyReady===true&&!err&&JSON.stringify(ready.data)===JSON.stringify(fx.full),'offline: full history restores from verified chunk cache');
 await rejects(()=>createCurrentFirstLoader({policy:p,store:mem(),fetcher:down,location:LOC,decrypt}).loadCurrent(),/offline/,'offline with nothing saved still throws (no figures invented)');
 // invalid NEW root on the wire (same generation, different bytes): fall back to saved, never throw away verified data
 const old=fixture({gen:7,sid:'SID2'});
 const r2=await createCurrentFirstLoader({policy:p,store,fetcher:mkFetch(old),location:LOC,decrypt}).loadCurrent();
 ok(r2.stale===true&&/bootstrap hash mismatch|generation conflict/.test(r2.status)&&r2.data.history.length===2,'conflicting new root: saved data shown stale, reason named');
 const skip=fixture({gen:9,prev:{generation:7,sha256:'c'.repeat(64)}});
 const r3=await createCurrentFirstLoader({policy:p,store,fetcher:mkFetch(skip),location:LOC,decrypt}).loadCurrent();
 ok(r3.stale===true&&/ancestry/.test(r3.status),'bad-ancestry root: saved data shown stale, reason named');
}
{ // partial background: never full-ready from partial, offline fallback stays retryable
 const fx=fixture(),store=mem(),down=new Set([Object.keys(fx.chunks)[2]]);const p=policyFor(fx);
 let err=null,ready=null;
 const L=createCurrentFirstLoader({policy:p,store,fetcher:mkFetch(fx,down),location:LOC,decrypt});
 await L.loadCurrent({onHistoryReady:r=>{ready=r},onHistoryError:e=>{err=e}});await wait(50);
 ok(err&&store.acc.full===null,'partial background: no full acceptance');
 const off=async()=>{throw Error('offline')};
 let ready2=null,err2=null;
 const r=await createCurrentFirstLoader({policy:p,store,fetcher:off,location:LOC,decrypt}).loadCurrent({onHistoryReady:x=>{ready2=x},onHistoryError:e=>{err2=e}});
 ok(r.stale===true&&r.data.history.length===2,'partial then offline: current figures still shown stale');
 await wait(50);
 ok(!ready2&&err2?.historyState==='error'&&store.acc.full===null,'partial then offline: history never ready from partial, retryable error');
}
{ // race: a newer load supersedes older hydration callbacks
 const fx=fixture(),store=mem();let a=0;
 const slow=(f=>async u=>{await wait(u.includes('archives')?20:0);return f(u)})(mkFetch(fx));
 const L=createCurrentFirstLoader({policy:policyFor(fx),store,fetcher:slow,location:LOC,decrypt});
 await L.loadCurrent({onHistoryReady:()=>{a++}});await L.loadCurrent({onHistoryReady:()=>{a+=10}});await wait(300);
 ok(a===10,'superseded load never fires its onHistoryReady');
}
{ // race: stale fallback hydration superseded by a fresh online load
 const fx=fixture(),base=mem();const p=policyFor(fx);
 await createCurrentFirstLoader({policy:p,store:base,fetcher:mkFetch(fx),location:LOC,decrypt}).loadCurrent();await wait(50);
 const slowStore={...base,readChunks:async()=>{await wait(60);return base.readChunks()}};
 let calls=0,rootCalls=0;
 const flaky=async u=>{if(u.includes('feed-current')){rootCalls++;if(rootCalls===1)throw Error('offline');await wait(10);}return mkFetch(fx)(u)};
 const L=createCurrentFirstLoader({policy:p,store:slowStore,fetcher:flaky,location:LOC,decrypt});
 const r1=await L.loadCurrent({onHistoryReady:()=>{calls++}});   // stale path (first root call fails)
 ok(r1.stale===true,'first load went stale');
 const r2=await L.loadCurrent({onHistoryReady:()=>{calls+=10}}); // fresh path supersedes while stale hydration waits on cache
 await wait(400);
 ok(r2.stale===false&&calls===10,'fresh load supersedes stale fallback hydration');
}
console.log(`\n${pass} passed, ${fails} failed`);process.exit(fails?1:0);
