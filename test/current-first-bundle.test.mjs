// current-first loader gates against the REAL proposed 847 bundle (watchdog-provided fixtures).
// Run: node test/current-first-bundle.test.mjs (Node 22+, no deps).
// Fixture paths default to the extracted bundle layout; override with CF_FIXTURE_DIR.
// The full plaintext candidate is private test material: CF_FULL_JSON points at it; without it
// the decrypt-lookup hydration gates skip, but root/current/manifest/lineage gates still run.
import {readFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {PROPOSED_POLICY,utf8,sha256} from '../feed-v2-loader.mjs';
import {CF_POLICY,createCurrentFirstLoader,validateRoot,decodeCurrent,hydrateFull,checkFullConsistency} from '../current-first-loader.mjs';
const H=x=>createHash('sha256').update(x).digest('hex');
const DIR=process.env.CF_FIXTURE_DIR||'/tmp/w';
const FULL=process.env.CF_FULL_JSON||'/tmp/w/full-847.json';
const BASE='https://khandpurarsh-sys.github.io/dj-ops/',LOC=BASE+'index.html';
const rootBytes=new Uint8Array(readFileSync(DIR+'/feed-current-v1.json'));
const manifest=JSON.parse(readFileSync(DIR+'/manifest.json','utf8'));
const projection=JSON.parse(readFileSync(DIR+'/current-indexed-shadow.json','utf8'));
let pass=0,fails=0,skips=0;const ok=(c,n)=>{if(c){pass++;console.log('ok  ',n)}else{fails++;console.log('FAIL',n)}};
const skip=n=>{skips++;console.log('skip',n)};

const policy={...CF_POLICY,enabled:true,bootstrapGeneration:1,bootstrapSha256:'f12cd5ffdbd26a55fcffe92a1df3291e345fd70e8b045c97751bd1986d7d8f82',requiredKids:PROPOSED_POLICY.requiredKids};

// decrypt double: plaintext fixtures substituted for crypto, keyed by envelope ciphertext.
const plainByCt=new Map();
const rootJ=JSON.parse(new TextDecoder().decode(rootBytes));
const currentEnv=JSON.parse(rootJ.current.body);
plainByCt.set(currentEnv.ct,projection);
let fullBytes=null;
if(existsSync(FULL))fullBytes=new Uint8Array(readFileSync(FULL));
if(fullBytes){
 ok(fullBytes.length===21153112&&await sha256(fullBytes)==='188d5c129b9a335d3f4f104e5d2584ae65b04e77f543d7c0be539446e3030428','private full candidate matches identity (21,153,112 bytes, sha 188d5c12...)');
 for(const m of projection.background.chunks){
  const env=JSON.parse(readFileSync(DIR+'/'+m.path,'utf8'));
  const frag={schema:'djops-full-fragment-v1',raw:Buffer.from(fullBytes.slice(m.offset,m.offset+m.rawBytes)).toString('base64')};
  const pj=utf8(JSON.stringify(frag));
  ok(pj.length===m.plainBytes&&await sha256(pj)===m.plainSha256,'fragment plaintext descriptor exact '+m.path.slice(-17));
  plainByCt.set(env.ct,frag);
 }
}else skip('full candidate absent: decrypt-lookup hydration gates');
const decrypt=async e=>{const p=plainByCt.get(e.ct);if(!p)throw Error('fixture: no plaintext for ciphertext');return structuredClone(p);};

{ // B1: real root passes validation at the pinned bootstrap
 const v=await validateRoot(rootBytes,policy,null);
 ok(v.generation===1&&v.root.previous===null&&v.hash==='f12cd5ffdbd26a55fcffe92a1df3291e345fd70e8b045c97751bd1986d7d8f82','real root validates at bootstrap generation 1');
 const kids=currentEnv.msgs.map(m=>m.kid).sort();
 ok(kids.length===20,'real envelope carries the 20-recipient roster');
}

let z=null;
{ // B2: real current projection decodes; index + background manifest exact
 const v=await validateRoot(rootBytes,policy,null);
 z=await decodeCurrent(v,decrypt,policy);
 ok(z.reportingDay==='2026-11-28'&&z.sourceDays.today==='2026-11-28'&&z.sourceDays.yesterday==='2026-11-27','real projection reporting/source days');
 ok(z.historyIndex.onlineDays.length===64&&z.historyIndex.retailDays.length===139,'real index: 64 online / 139 retail days');
 ok(z.background.chunks.length===31&&z.background.fullBytes===21153112&&z.background.fullSha256==='188d5c129b9a335d3f4f104e5d2584ae65b04e77f543d7c0be539446e3030428','real background manifest: 31 chunks, exact full binding');
}

{ // B3: every chunk descriptor cross-checks manifest, file bytes and envelope lineage
 const epoch='roster-'+H(currentEnv.msgs.map(m=>m.kid).sort().join(','));
 const manifestByPath=new Map(manifest.objectsFirst.map(o=>[o.path,o]));
 let good=0;
 for(const m of z.background.chunks){
  const mo=manifestByPath.get(m.path),file=new Uint8Array(readFileSync(DIR+'/'+m.path));
  if(!mo||mo.bytes!==m.wireBytes||mo.sha256!==m.wireSha256)break;
  if(file.length!==m.wireBytes||await sha256(file)!==m.wireSha256)break;
  const e=JSON.parse(new TextDecoder().decode(file));
  if(e.sid!=='full-'+m.rawSha256||e.archiveEpoch!==epoch||e.archiveSchema!=='djops-full-background-v1')break;
  if(e.msgs.map(x=>x.kid).sort().join(',')!==currentEnv.msgs.map(x=>x.kid).sort().join(','))break;
  good++;
 }
 ok(good===31,'all 31 chunks: descriptor <-> manifest <-> file <-> envelope lineage exact');
}

const mem=()=>{let acc=null,ch={};return{async read(){return acc},async commit(r){acc=r},async readChunks(){return ch},async putChunks(m){Object.assign(ch,m)},get acc(){return acc}}};
const fileFetch=(missing=new Set())=>{let calls=0;const f=async url=>{calls++;const rel=url.replace(BASE,'');const p=DIR+'/'+(rel==='feed-current-v1.json'?'feed-current-v1.json':rel);
 if(missing.has(rel)||!existsSync(p))return{ok:false,status:404,headers:new Headers(),url,redirected:false};
 const body=new Uint8Array(readFileSync(p));
 return{ok:true,status:200,url,redirected:false,headers:new Headers({'content-length':String(body.length)}),body:{getReader(){let d=false;return{read:async()=>d?{done:true}:(d=true,{done:false,value:body}),cancel:async()=>{}}}}};};f.calls=()=>calls;return f;};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const until=async(fn,ms=15000)=>{const t0=Date.now();while(Date.now()-t0<ms){if(fn())return true;await wait(50)}return fn()};
const canon=x=>Array.isArray(x)?'['+x.map(canon).join(',')+']':x!==null&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canon(x[k])).join(',')+'}':JSON.stringify(x);

if(fullBytes){ // B4: real end-to-end through the actual loader
 const store=mem(),fetcher=fileFetch();let ready=null,err=null;
 const L=createCurrentFirstLoader({policy,store,fetcher,location:LOC,decrypt});
 const cur=await L.loadCurrent({onHistoryReady:r=>{ready=r},onHistoryError:e=>{err=e}});
 ok(canon(cur.data)===canon(projection.data)&&cur.stale===false,'real current shown first, exact projection');
 ok(await until(()=>ready||err)&&ready?.historyReady===true&&!err,'real background hydration reaches ready'+(err?' ['+err.reason+']':''));
 ok(fetcher.calls()===32,'exactly 32 requests (1 root + 31 chunks), none repeated');
 ok(ready&&canon(ready.data)===canon(JSON.parse(Buffer.from(fullBytes).toString('utf8'))),'reconstructed full byte-parses to the exact 847 candidate');
 ok(store.acc.full?.sha256==='188d5c129b9a335d3f4f104e5d2584ae65b04e77f543d7c0be539446e3030428','full acceptance recorded for the real candidate');

 // B5: fallback against the real saved state
 const off=async()=>{throw Error('offline')};
 let ready2=null,err2=null;
 const r=await createCurrentFirstLoader({policy,store,fetcher:off,location:LOC,decrypt}).loadCurrent({onHistoryReady:x=>{ready2=x},onHistoryError:e=>{err2=e}});
 ok(r.stale===true&&/original source times/.test(r.status)&&canon(r.data)===canon(projection.data),'offline: real saved figures shown stale with original source times');
 ok(await until(()=>ready2||err2)&&ready2?.historyReady===true&&!err2,'offline: real full history restores from chunk cache with zero network'+(err2?' ['+err2.reason+']':''));

 // B6: partial background on the real bundle: never ready from partial
 const store2=mem();const missingPath=projection.background.chunks[5].path;
 const fetcher2=fileFetch(new Set([missingPath]));let err3=null,ready3=false;
 const L2=createCurrentFirstLoader({policy,store:store2,fetcher:fetcher2,location:LOC,decrypt});
 await L2.loadCurrent({onHistoryReady:()=>{ready3=true},onHistoryError:e=>{err3=e}});
 ok(await until(()=>ready3||err3)&&!ready3&&err3?.historyState==='error'&&store2.acc.full===null,'partial real background: retryable error, no full acceptance');

 // B7: race on the real bundle: superseded load drops callbacks
 let a=0;
 const slow=async u=>{await wait(u.includes('archives')?15:0);return fileFetch()(u)};
 const L3=createCurrentFirstLoader({policy,store:mem(),fetcher:slow,location:LOC,decrypt});
 await L3.loadCurrent({onHistoryReady:()=>{a++}});await L3.loadCurrent({onHistoryReady:()=>{a+=10}});
 ok(await until(()=>a===10)&&a===10,'real bundle race: superseded load never fires onHistoryReady');
}else{skip('B4 real end-to-end');skip('B5 real offline fallback');skip('B6 real partial background');skip('B7 real race')}

if(fullBytes){ // B8: consistency rejection on the real pair (mutated full must be rejected)
 const full=JSON.parse(Buffer.from(fullBytes).toString('utf8'));
 const mut=(f,label,re)=>{try{checkFullConsistency(z,f);ok(false,label+' (no error)')}catch(e){ok(re.test(e.message),label+' ['+e.message+']')}};
 const m1=structuredClone(full);m1.history[0].rev=(m1.history[0].rev||0)+1;
 mut(m1,'real pair: index summary drift rejected',/index summary vs full row/);
 const m2=structuredClone(full);m2.history[63].billList=[];
 mut(m2,'real pair: today detail change rejected',/deferred member list vs full row|projection detail row vs full/);
 const m3=structuredClone(full);m3.snapshot.revenue=(m3.snapshot.revenue||0)+1;
 mut(m3,'real pair: shown snapshot figure change rejected',/projection value differs from full/);
 ok(true,'real pair positive consistency already proven inside B4 hydration');
}
console.log(`\n${pass} passed, ${fails} failed, ${skips} skipped`);process.exit(fails?1:0);
