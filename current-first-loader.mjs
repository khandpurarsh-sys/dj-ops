/* Current-first reader (djops-current-first-v1), draft 1. Built to CONTRACT.md (shadow).
   OFF until a separately approved release pins the bootstrap hash and policy. It reads
   feed-current-v1.json only and never touches feed-v2.json, so installed v2 clients are
   unaffected. No figures are shown from cache before the network-validated current root. */
import {sha256,utf8,fetchBounded,envelope,approvedRoster} from './feed-v2-loader.mjs';

export const CF_POLICY=Object.freeze({enabled:false,repo:'khandpurarsh-sys/dj-ops',origin:'https://khandpurarsh-sys.github.io',basePath:'/dj-ops/',policyVersion:'djops-current-first-policy-1',bootstrapGeneration:null,bootstrapSha256:null,maxFeedBytes:2097152,maxBodyBytes:1048576,maxPlaintextBytes:8388608,maxFullBytes:33554432,maxChunks:64,timeoutMs:15000,requiredKids:[]});
const HEX=/^[a-f0-9]{64}$/,ISO_DAY=/^\d{4}-\d{2}-\d{2}$/,PATH=/^archives\/current-first-v1\/[a-f0-9]{64}\.json$/;
const fail=s=>{throw Error('Current-first: '+s)};
const integer=x=>Number.isSafeInteger(x)&&x>0,nat=x=>Number.isSafeInteger(x)&&x>=0;
const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const time=x=>typeof x==='string'&&/(Z|[+-]\d{2}:\d{2})$/.test(x)&&Number.isFinite(Date.parse(x));
const exact=(o,k)=>plain(o)&&Object.keys(o).sort().join(',')===k.slice().sort().join(',');
const day=x=>typeof x==='string'&&ISO_DAY.test(x)&&Number.isFinite(Date.parse(x+'T12:00:00Z'));
const dec=b=>new TextDecoder('utf-8',{fatal:true}).decode(b);
const unb64=s=>{if(typeof s!=='string'||s.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(s))fail('fragment base64');return Uint8Array.from(atob(s),c=>c.charCodeAt(0));};

export function checkCfPolicy(p){
 if(!p.enabled)fail('reader disabled');
 if(p.repo!=='khandpurarsh-sys/dj-ops'||p.origin!=='https://khandpurarsh-sys.github.io'||p.basePath!=='/dj-ops/')fail('unapproved origin/repo');
 if(p.policyVersion!=='djops-current-first-policy-1')fail('policy version');
 if(!integer(p.bootstrapGeneration)||!HEX.test(p.bootstrapSha256))fail('bootstrap approval missing');
 if(!Array.isArray(p.requiredKids)||!p.requiredKids.length)fail('approved recipient set missing');
 for(const k of ['maxFeedBytes','maxBodyBytes','maxPlaintextBytes','maxFullBytes','maxChunks','timeoutMs'])if(!integer(p[k]))fail('limits missing');
}
export function resolveRoot(p,location){
 const here=new URL(location),url=new URL('feed-current-v1.json',here);
 if(here.origin!==p.origin||!here.pathname.startsWith(p.basePath)||url.pathname!==p.basePath+'feed-current-v1.json')fail('endpoint not pinned');
 return url.href;
}
const v2p=p=>({requiredKids:p.requiredKids,...p}); // envelope()/approvedRoster() read requiredKids

function checkRow(n,row,p,accepted){
 if(!plain(row)||typeof row.body!=='string'||!integer(row.byteLength)||row.byteLength>p.maxBodyBytes||utf8(row.body).length!==row.byteLength||!HEX.test(row.sha256)||!time(row.publishedAt))fail('aux row '+n);
 if(!exact(row.source,['kind','commentId','owner'])||row.source.kind!=='github-comment'||!integer(row.source.commentId)||row.source.owner!=='khandpurarsh-sys')fail('aux source '+n);
 const prev=accepted?.aux?.[n];
 if(prev&&(row.source.commentId<prev.commentId||(row.source.commentId===prev.commentId&&row.sha256!==prev.sha256)))fail('aux regression/conflict '+n);
}
export async function validateRoot(bytes,p,accepted=null){
 checkCfPolicy(p);if(!(bytes instanceof Uint8Array)||bytes.byteLength>p.maxFeedBytes)fail('response limit');
 let j;try{j=JSON.parse(dec(bytes))}catch{fail('root JSON/UTF-8')}
 const hash=await sha256(bytes);
 if(!exact(j,['schema','repo','policyVersion','generation','previous','sid','publishedAt','sourceV2','current','aux'])||j.schema!=='djops-current-first-v1'||j.repo!==p.repo||j.policyVersion!==p.policyVersion||!integer(j.generation)||typeof j.sid!=='string'||!j.sid||!time(j.publishedAt))fail('root format');
 if(!exact(j.sourceV2,['generation','sha256'])||!integer(j.sourceV2.generation)||!HEX.test(j.sourceV2.sha256))fail('sourceV2 binding');
 if(j.generation<p.bootstrapGeneration)fail('below bootstrap floor');
 if(j.generation===p.bootstrapGeneration&&hash!==p.bootstrapSha256)fail('bootstrap hash mismatch');
 if(j.previous===null){if(j.generation!==p.bootstrapGeneration)fail('previous missing outside bootstrap')}
 else if(!exact(j.previous,['generation','sha256'])||j.previous.generation!==j.generation-1||!HEX.test(j.previous.sha256))fail('ancestry');
 if(accepted){
  if(!integer(accepted.generation)||!HEX.test(accepted.rootSha256))fail('saved acceptance invalid');
  if(j.generation<accepted.generation)fail('generation rollback');
  if(j.generation===accepted.generation&&hash!==accepted.rootSha256)fail('generation conflict');
  if(j.generation===accepted.generation+1&&(j.previous?.generation!==accepted.generation||j.previous.sha256!==accepted.rootSha256))fail('previous hash mismatch');
 }
 const c=j.current;
 if(!exact(c,['body','byteLength','sha256'])||typeof c.body!=='string'||!integer(c.byteLength)||c.byteLength>p.maxBodyBytes||utf8(c.body).length!==c.byteLength||!HEX.test(c.sha256)||await sha256(utf8(c.body))!==c.sha256)fail('current body hash/length');
 const e=envelope(c.body,true,v2p(p));if(e.sid!==j.sid)fail('current envelope sid');
 if(!exact(j.aux,['2','87','88']))fail('aux rows');for(const n of ['2','87','88']){checkRow(n,j.aux[n],p,accepted);if(await sha256(utf8(j.aux[n].body))!==j.aux[n].sha256)fail('aux hash '+n);envelope(j.aux[n].body,false,v2p(p));}
 return {root:j,hash,generation:j.generation,env:e};
}

function checkIndex(h){
 if(!exact(h,['schema','onlineDays','retailDays','detailMode'])||h.schema!=='djops-history-index-v1'||h.detailMode!=='automatic-background'||!Array.isArray(h.onlineDays)||!Array.isArray(h.retailDays))fail('history index format');
 const online=['billList','cancelledOrders','finalOrders','postCloseCurrentObservation'],retail=['billList','itemOnlyExchanges','unmatchedItemRows','zeroNet179Only','missingItemAmounts'];
 for(const [list,ban] of [[h.onlineDays,online],[h.retailDays,retail]])list.forEach((r,i)=>{
  if(!exact(r,['ordinal','day','summary','deferredMembers','detailIncluded'])||r.ordinal!==i||!day(r.day)||!plain(r.summary)||!Array.isArray(r.deferredMembers)||typeof r.detailIncluded!=='boolean')fail('history index entry');
  if(!r.detailIncluded&&ban.some(k=>k in r.summary))fail('index summary carries deferred member');
 });
}
function checkBackground(b,p){
 if(!exact(b,['schema','format','fullBytes','fullSha256','chunks'])||b.schema!=='djops-full-background-v1'||b.format!=='concatenate-raw-chunks-v1'||!integer(b.fullBytes)||b.fullBytes>p.maxFullBytes||!HEX.test(b.fullSha256)||!Array.isArray(b.chunks)||!b.chunks.length||b.chunks.length>p.maxChunks)fail('background manifest');
 let at=0;const seen=new Set();
 for(const m of b.chunks){
  if(!exact(m,['path','wireBytes','wireSha256','plainBytes','plainSha256','offset','rawBytes','rawSha256'])||typeof m.path!=='string'||!PATH.test(m.path)||seen.has(m.path)||!integer(m.wireBytes)||m.wireBytes>p.maxBodyBytes||!HEX.test(m.wireSha256)||!integer(m.plainBytes)||!HEX.test(m.plainSha256)||!nat(m.offset)||!integer(m.rawBytes)||!HEX.test(m.rawSha256))fail('background chunk descriptor');
  if(m.path!=='archives/current-first-v1/'+m.wireSha256+'.json')fail('background chunk path/hash');
  if(m.offset!==at)fail('background chunks not contiguous');at+=m.rawBytes;seen.add(m.path);
 }
 if(at!==b.fullBytes)fail('background byte total');
}
export async function decodeCurrent(v,decrypt,p){
 const z=await decrypt(v.env,p.maxPlaintextBytes);
 if(!exact(z,['schema','generation','sid','reportingDay','sourceDays','data','historyIndex','background'])||z.schema!=='djops-current-projection-v1'||z.generation!==v.generation||z.sid!==v.root.sid||!day(z.reportingDay)||!exact(z.sourceDays,['today','yesterday'])||!day(z.sourceDays.today)||!day(z.sourceDays.yesterday)||!plain(z.data))fail('current projection format');
 checkIndex(z.historyIndex);checkBackground(z.background,p);return z;
}
/* Fetch, verify and reassemble the full original candidate. Never parses a fragment alone. */
export async function hydrateFull(z,v,decrypt,p,fetcher,location,chunkCache=null){
 const b=z.background,here=new URL(location);if(here.origin!==p.origin||!here.pathname.startsWith(p.basePath))fail('background origin');
 const kids=v.env.msgs.map(m=>m.kid).sort(),epoch='roster-'+await sha256(utf8(kids.join(',')));
 const out=new Uint8Array(b.fullBytes),wires={};
 for(const m of b.chunks){
  const url=new URL(m.path,new URL(p.basePath,p.origin));if(url.origin!==p.origin||url.pathname!==p.basePath+m.path||url.search||url.hash)fail('background path');
  let wire=chunkCache?.[m.path]!==undefined?utf8(chunkCache[m.path]):await fetchBounded(url.href,{...p,maxFeedBytes:p.maxBodyBytes},fetcher);
  if(wire.length!==m.wireBytes||await sha256(wire)!==m.wireSha256)fail('background wire integrity');
  let text;try{text=dec(wire)}catch{fail('background wire utf8')}
  const e=envelope(text,true,v2p(p));
  if(e.archiveSchema!=='djops-full-background-v1'||e.sid!=='full-'+m.rawSha256||e.archiveEpoch!==epoch||e.msgs.map(x=>x.kid).sort().join(',')!==kids.join(','))fail('background chunk lineage');
  const f=await decrypt(e,p.maxPlaintextBytes);
  if(!exact(f,['schema','raw'])||f.schema!=='djops-full-fragment-v1')fail('background fragment format');
  const pj=utf8(JSON.stringify(f));if(pj.length!==m.plainBytes||await sha256(pj)!==m.plainSha256)fail('background plaintext integrity');
  const raw=unb64(f.raw);if(raw.length!==m.rawBytes||await sha256(raw)!==m.rawSha256)fail('background raw integrity');
  out.set(raw,m.offset);wires[m.path]=text;
 }
 if(await sha256(out)!==b.fullSha256)fail('background reconstruction hash');
 let full;try{full=JSON.parse(dec(out))}catch{fail('background reconstruction JSON')}
 if(!plain(full)||!Array.isArray(full.history)||!Array.isArray(full.retailHistory)||full.history.length!==z.historyIndex.onlineDays.length||full.retailHistory.length!==z.historyIndex.retailDays.length)fail('reconstructed shape vs index');
 return {data:full,chunks:wires};
}

/* Store: high-water only (no figures) plus immutable verified chunk wire cache. */
export function cfStore(indexedDB){
 const opened=new Promise((res,rej)=>{const q=indexedDB.open('dressjet-current-first-v1',1);q.onupgradeneeded=()=>{for(const s of ['accepted','chunks'])if(!q.result.objectStoreNames.contains(s))q.result.createObjectStore(s)};q.onerror=()=>rej(q.error);q.onsuccess=()=>res(q.result);q.onblocked=()=>rej(Error('Current-first: storage upgrade blocked'));});
 const tx=async(s,mode,fn)=>{const db=await opened;return new Promise((res,rej)=>{const t=db.transaction(s,mode);let out;fn(t,v=>{out=v});t.oncomplete=()=>res(out);t.onerror=()=>rej(t.error);t.onabort=()=>rej(t.error||Error('Current-first: storage aborted'));});};
 return{read:repo=>tx('accepted','readonly',(t,o)=>{const q=t.objectStore('accepted').get(repo);q.onsuccess=()=>o(q.result||null)}),
  commit:record=>tx('accepted','readwrite',(t)=>{const s=t.objectStore('accepted'),q=s.get(record.repo);q.onsuccess=()=>{const old=q.result;if(old&&(old.generation>record.generation||(old.generation===record.generation&&old.rootSha256!==record.rootSha256)||(record.generation===old.generation+1&&(record.previous?.generation!==old.generation||record.previous?.sha256!==old.rootSha256)))){t.abort();return}s.put(record,record.repo)}}),
  readChunks:()=>tx('chunks','readonly',(t,o)=>{const q=t.objectStore('chunks').getAll(),k=t.objectStore('chunks').getAllKeys();q.onsuccess=()=>{k.onsuccess=()=>{const m={};k.result.forEach((x,i)=>m[x]=q.result[i]);o(m)}}}),
  putChunks:m=>tx('chunks','readwrite',t=>{const s=t.objectStore('chunks');for(const [k,v] of Object.entries(m))s.put(v,k)})};
}
function stateFrom(v){const aux={};for(const n of ['2','87','88'])aux[n]={commentId:v.root.aux[n].source.commentId,sha256:v.root.aux[n].sha256};return{repo:v.root.repo,generation:v.generation,rootSha256:v.hash,sid:v.root.sid,aux,previous:v.root.previous,full:null};}

/* loadCurrent resolves only after root+current validation and the atomic high-water commit.
   Hydration then starts by itself. A newer loadCurrent supersedes an older one: its callbacks
   are dropped (identity check), and a partial background never writes any accepted state. */
export function createCurrentFirstLoader({policy,store,fetcher=fetch,location,decrypt}){
 let active=null;
 async function hydrate(run,cb){
  const same=()=>active===run;
  try{
   const cache=await store.readChunks().catch(()=>null);
   const h=await hydrateFull(run.z,run.v,decrypt,policy,fetcher,location,cache);
   if(!same())return;
   await store.commit({...stateFrom(run.v),full:{sha256:run.z.background.fullSha256,bytes:run.z.background.fullBytes}});
   await store.putChunks(h.chunks).catch(()=>{});
   if(!same())return;
   run.state='ready';cb.onHistoryReady?.({data:h.data,generation:run.v.generation,sid:run.v.root.sid,rootSha256:run.v.hash,historyReady:true,historyState:'ready'});
  }catch(e){if(!same())return;run.state='error';run.reason=e.message;cb.onHistoryError?.({generation:run.v.generation,sid:run.v.root.sid,rootSha256:run.v.hash,historyReady:false,historyState:'error',reason:e.message});}
 }
 return{
  async loadCurrent(cb={}){
   checkCfPolicy(policy);
   const saved=await store.read(policy.repo);
   const bytes=await fetchBounded(resolveRoot(policy,location),policy,fetcher);   // no cache fallback: failure throws
   const v=await validateRoot(bytes,policy,saved),z=await decodeCurrent(v,decrypt,policy);
   await store.commit(stateFrom(v));
   const run={v,z,cb,state:'loading'};active=run;
   queueMicrotask(()=>hydrate(run,cb));
   return{data:z.data,historyIndex:z.historyIndex,reportingDay:z.reportingDay,sourceDays:z.sourceDays,aux:v.root.aux,generation:v.generation,sid:v.root.sid,rootSha256:v.hash,historyReady:false,historyState:'loading'};
  },
  retryHistory(){if(!active||active.state!=='error')return false;active.state='loading';queueMicrotask(()=>hydrate(active,active.cb));return true;},
  historyState(){return active?active.state:'none'}
 };
}
