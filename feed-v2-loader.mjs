/* Proposed reader only. OFF until a separately approved release supplies anchors,
   measured limits and a bounded decryptor. No publisher, keys or network writes. */
export const PROPOSED_POLICY=Object.freeze({"enabled":true,"cutover":true,"repo":"khandpurarsh-sys/dj-ops","origin":"https://khandpurarsh-sys.github.io","basePath":"/dj-ops/","policyVersion":"dressjet-static-v2-proposed-1","bootstrapGeneration":1,"bootstrapSha256":"60c8e8571119d0a60a9055eaf7dc1108e9a16e54e9783b29b9b18029d522321b","maxFeedBytes":2097152,"maxBodyBytes":1048576,"maxPlaintextBytes":8388608,"timeoutMs":15000,"boundedDecryptorVerified":true,"requiredKids":["8GOA2Gtn","BdzJ1fS2","DtFLt6s3","NczC6Ww8","R8McjQ4b","ZVx5xiim","eKlKbhWk","emuDKqXq","gejFeX4x","jkSP8g0I","oYAlwWHx","qASYbNhs","uzTFaoki","x8pxzyEM","xZw9PRCY","yKOhpUFs","zsExOo1d"]});
const OPTIONAL_REMOVALS=Object.freeze(['eKlKbhWk','xZw9PRCY','NczC6Ww8','yKOhpUFs','gejFeX4x','BdzJ1fS2']);
// Optional adds: yxNJE9dV (3 Nov iPhone rotation); tHhbQ90n (10 Nov, owner-signed add of the
// "dad" DRJ device, approval seq 1794318511225, verified against the pinned owner key);
// ai6ADtGq (21 Nov, owner-signed add of the "My Duo" iPhone, approval seq 1795237430140,
// verified against the pinned owner key); b4DNM6EB (25 Nov, owner-signed add of the
// "Anu duo" iPhone, approval seq 1795623441123, verified against the pinned owner key).
const OPTIONAL_ADDS=Object.freeze(['yxNJE9dV','tHhbQ90n','ai6ADtGq','b4DNM6EB']);
export function approvedRoster(kids,p){
 const set=new Set(kids),old=p.requiredKids;
 if(set.size!==kids.length||kids.some(k=>!old.includes(k)&&!OPTIONAL_ADDS.includes(k)))return false;
 if(old.some(k=>!OPTIONAL_REMOVALS.includes(k)&&!set.has(k)))return false;
 return true;
}
const enc=new TextEncoder(),ROWS=['1','2','3','87','88'],HEX=/^[a-f0-9]{64}$/;
export const utf8=s=>enc.encode(s);
export async function sha256(bytes){const d=await crypto.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(d),b=>b.toString(16).padStart(2,'0')).join('');}
export function fail(s){throw Error('Static v2: '+s)}
function integer(x){return Number.isSafeInteger(x)&&x>0}
function plain(x){return x!==null&&typeof x==='object'&&!Array.isArray(x)}
function time(x){return typeof x==='string'&&/(Z|[+-]\d{2}:\d{2})$/.test(x)&&Number.isFinite(Date.parse(x))}
function exactKeys(o,keys){return plain(o)&&Object.keys(o).sort().join(',')===keys.slice().sort().join(',')}
export function checkPolicy(p){
 if(!p.enabled)fail('reader disabled');
 if(p.repo!=='khandpurarsh-sys/dj-ops'||p.origin!=='https://khandpurarsh-sys.github.io'||p.basePath!=='/dj-ops/')fail('unapproved origin/repo');
 if(!integer(p.bootstrapGeneration)||!HEX.test(p.bootstrapSha256))fail('bootstrap approval missing');
 if(!p.boundedDecryptorVerified)fail('bounded decoder approval missing');
 if(!Array.isArray(p.requiredKids)||p.requiredKids.length!==17||new Set(p.requiredKids).size!==17||p.requiredKids.some(k=>typeof k!=='string'||!k))fail('approved recipient set missing');
 for(const k of ['maxFeedBytes','maxBodyBytes','maxPlaintextBytes','timeoutMs'])if(!integer(p[k]))fail('limits missing');
}
export function resolveEndpoint(p,location){
 const here=new URL(location),url=new URL('feed-v2.json',here);
 if(here.origin!==p.origin||!here.pathname.startsWith(p.basePath)||url.origin!==p.origin||url.pathname!==p.basePath+'feed-v2.json')fail('endpoint not pinned');
 return url.href;
}
export async function fetchBounded(url,p,fetcher=fetch){
 const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),p.timeoutMs);let reader;
 try{
  const r=await fetcher(url,{cache:'no-store',redirect:'error',credentials:'omit',signal:abort.signal});
  if(!r.ok)fail('HTTP '+r.status);if(r.redirected||(r.url&&r.url!==url))fail('redirect');
  const declared=r.headers?.get('content-length');if(declared!==null&&declared!==undefined&&(!/^\d+$/.test(declared)||Number(declared)>p.maxFeedBytes))fail('response length');
  if(!r.body?.getReader)fail('streaming response required');reader=r.body.getReader();let count=0;const chunks=[];
  while(true){if(abort.signal.aborted)fail('timeout');const {value,done}=await reader.read();if(done)break;if(!(value instanceof Uint8Array))fail('invalid byte stream');count+=value.byteLength;if(count>p.maxFeedBytes)fail('response limit');chunks.push(value);}
  const bytes=new Uint8Array(count);let at=0;for(const b of chunks){bytes.set(b,at);at+=b.byteLength;}return bytes;
 }finally{clearTimeout(timer);if(reader)await reader.cancel().catch(()=>{});}
}
export function envelope(body,main,p){
 let e;try{e=JSON.parse(body)}catch{fail('envelope JSON')}
 if(!plain(e)||!Array.isArray(e.msgs)||!e.msgs.length||!e.msgs.every(m=>plain(m)&&typeof m.kid==='string'&&plain(m.epk)&&typeof m.epk.x==='string'&&typeof m.epk.y==='string'&&typeof m.iv==='string'&&(typeof m.wk==='string'||typeof m.ct==='string')))fail('envelope fields');
 if(new Set(e.msgs.map(m=>m.kid)).size!==e.msgs.length)fail('duplicate recipient');
 if(main&&(e.v!==2||e.z!==1||typeof e.ct!=='string'||!e.ct||typeof e.iv!=='string'||!e.iv||!e.sid||typeof e.sid!=='string'))fail('main envelope fields');
 if(main&&!approvedRoster(e.msgs.map(m=>m.kid),p))fail('recipient set');
 return e;
}
export async function validateFeed(bytes,p,accepted=null){
 checkPolicy(p);if(!(bytes instanceof Uint8Array)||bytes.byteLength>p.maxFeedBytes)fail('response limit');let raw,j;
 try{raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);j=JSON.parse(raw)}catch{fail('feed JSON/UTF-8')}
 const hash=await sha256(bytes);
 if(!plain(j)||j.version!==2||j.repo!==p.repo||j.policyVersion!==p.policyVersion||j.mode!=='static-primary'||!integer(j.generation)||!time(j.publishedAt)||typeof j.sid!=='string'||!j.sid||!exactKeys(j.rows,ROWS))fail('format');
 if(j.generation<p.bootstrapGeneration)fail('below bootstrap floor');
 if(j.generation===p.bootstrapGeneration&&hash!==p.bootstrapSha256)fail('bootstrap hash mismatch');
 if(j.generation===1){if(j.previous!==null)fail('genesis ancestry')}else if(!exactKeys(j.previous,['generation','sha256'])||j.previous.generation!==j.generation-1||!HEX.test(j.previous.sha256))fail('ancestry');
 if(accepted){
  if(accepted.repo!==p.repo||!integer(accepted.generation)||!HEX.test(accepted.feedSha256))fail('saved acceptance invalid');
  if(j.generation<accepted.generation)fail('generation rollback');
  if(j.generation===accepted.generation&&hash!==accepted.feedSha256)fail('generation conflict');
  if(j.generation===accepted.generation+1&&(j.previous?.generation!==accepted.generation||j.previous.sha256!==accepted.feedSha256))fail('previous hash mismatch');
 }
 for(const n of ROWS){const row=j.rows[n],main=n==='1'||n==='3';
  if(!plain(row)||typeof row.body!=='string'||!integer(row.byteLength)||row.byteLength>p.maxBodyBytes||utf8(row.body).length!==row.byteLength||!HEX.test(row.sha256)||await sha256(utf8(row.body))!==row.sha256||!time(row.publishedAt))fail('row hash/length/time');
  if('commentId' in row)fail('legacy commentId on v2 row');
  if(main){if(!exactKeys(row.source,['kind','generation'])||row.source.kind!=='static'||row.source.generation!==j.generation)fail('static source');}
  else {if(!exactKeys(row.source,['kind','commentId','owner'])||row.source.kind!=='github-comment'||!integer(row.source.commentId)||row.source.owner!=='khandpurarsh-sys')fail('aux source');
   const prev=accepted?.aux?.[n];if(prev&&(row.source.commentId<prev.commentId||(row.source.commentId===prev.commentId&&row.sha256!==prev.sha256)))fail('aux regression/conflict');}
  envelope(row.body,main,p);
 }
 const f=JSON.parse(j.rows['3'].body),s=JSON.parse(j.rows['1'].body);
 if(f.msgs.map(m=>m.kid).sort().join(',')!==s.msgs.map(m=>m.kid).sort().join(','))fail('main recipient mismatch');
 if(f.sid!==j.sid||s.sid!==j.sid||f.slim||s.slim!==1)fail('snapshots mismatch');
 return {feed:j,raw,hash,generation:j.generation};
}
function stateFrom(v){const aux={};for(const n of ['2','87','88'])aux[n]={commentId:v.feed.rows[n].source.commentId,sha256:v.feed.rows[n].sha256};return{repo:v.feed.repo,generation:v.generation,feedSha256:v.hash,sid:v.feed.sid,raw:v.raw,aux,previous:v.feed.previous};}
/* One encrypted record is both cache and high-water mark. IndexedDB serializes
   overlapping readwrite transactions so concurrent tabs cannot regress it. */
export function indexedStore(indexedDB){
 const opened=new Promise((resolve,reject)=>{const q=indexedDB.open('dressjet-static-v2',1);q.onupgradeneeded=()=>{if(!q.result.objectStoreNames.contains('accepted'))q.result.createObjectStore('accepted')};q.onerror=()=>reject(q.error);q.onsuccess=()=>resolve(q.result);q.onblocked=()=>reject(Error('Static v2: storage upgrade blocked'));});
 return{async read(repo){const db=await opened;return new Promise((resolve,reject)=>{const t=db.transaction('accepted','readonly'),q=t.objectStore('accepted').get(repo);let result=null;q.onsuccess=()=>{result=q.result||null};t.oncomplete=()=>resolve(result);t.onerror=()=>reject(t.error);t.onabort=()=>reject(t.error||Error('Static v2: storage aborted'));});},
 async commit(record){const db=await opened;return new Promise((resolve,reject)=>{const t=db.transaction('accepted','readwrite'),s=t.objectStore('accepted'),q=s.get(record.repo);let problem=null;
 q.onsuccess=()=>{const old=q.result;if(old&&(old.generation>record.generation||(old.generation===record.generation&&old.feedSha256!==record.feedSha256)||(record.generation===old.generation+1&&(record.previous?.generation!==old.generation||record.previous?.sha256!==old.feedSha256)))){problem=Error('Static v2: concurrent acceptance conflict');t.abort();return;}s.put(record,record.repo);};t.oncomplete=()=>resolve();t.onerror=()=>reject(t.error);t.onabort=()=>reject(problem||t.error||Error('Static v2: storage aborted'));});}};
}
async function decodeValidated(v,decrypt,p,fetcher,location,cached=null){
 /* decrypt must enforce maxPlaintextBytes WHILE inflating, before JSON allocation.
    The proposed crypto.js enforces this bound while inflating. Policy remains
    disabled until its reviewed build, anchors and device limits are approved;
    post-parse size is no cap. */
 const full=await decrypt(JSON.parse(v.feed.rows['3'].body),p.maxPlaintextBytes),slim=await decrypt(JSON.parse(v.feed.rows['1'].body),p.maxPlaintextBytes);
 if(!plain(full)||!plain(slim)||JSON.stringify(full)!==JSON.stringify(slim))fail('decrypted variants mismatch');
 if(full.archiveTransport)return hydrateArchive(full,v,decrypt,p,fetcher,location,cached);
 if(!full.snapshot)fail('snapshot missing');return {data:full,chunks:null};
}
export function createV2Loader({policy,store,fetcher=fetch,location,decrypt}){
 let acceptedFlight=null;
 return{async load(){checkPolicy(policy);const saved=await store.read(policy.repo);
 const run=async()=>{try{
  const bytes=await fetchBounded(resolveEndpoint(policy,location),policy,fetcher),v=await validateFeed(bytes,policy,saved),decoded=await decodeValidated(v,decrypt,policy,fetcher,location);
  const record=stateFrom(v);if(decoded.chunks)record.archiveChunks=decoded.chunks;await store.commit(record);return{data:decoded.data,feed:v.feed,body:v.feed.rows['3'].body,record,stale:false,status:''};
 }catch(error){
  const latest=await store.read(policy.repo);if(!latest)throw error;
  /* Cache is rehashed/validated/decrypted, never blindly trusted as JSON. */
  const v=await validateFeed(utf8(latest.raw),policy,latest),decoded=await decodeValidated(v,decrypt,policy,fetcher,location,latest.archiveChunks||{});
  return{data:decoded.data,feed:v.feed,body:v.feed.rows['3'].body,record:latest,stale:true,status:'Feed check failed: '+error.message+'. Showing last saved data with original source times'};
 }};if(acceptedFlight)return acceptedFlight;acceptedFlight=run();try{return await acceptedFlight}finally{acceptedFlight=null}
 },async blocksLegacy(){return policy.cutover||!!await store.read(policy.repo);}};
}

// Archive-v1 policy applies only to exact lossless reconstruction. Existing
// feed, encrypted-object and per-object inflate limits are unchanged.
export const ARCHIVE_V1_POLICY=Object.freeze({schema:'djops-retail-archive-v1',maxChunks:64,maxReconstructedBytes:33554432,maxChunkPlaintextBytes:1048576,maxEntries:1024});
const unbase64=s=>{if(typeof s!=='string'||s.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(s))fail('archive base64');return Uint8Array.from(atob(s),c=>c.charCodeAt(0));};
function concatBytes(parts){const n=parts.reduce((n,b)=>n+b.length,0),out=new Uint8Array(n);let at=0;for(const b of parts){out.set(b,at);at+=b.length;}return out;}
export async function hydrateArchive(wrapper,v,decrypt,p,fetcher,location,cached=null){
 const a=wrapper.archiveTransport,A=ARCHIVE_V1_POLICY;
 if(!exactKeys(wrapper,['archiveTransport'])||!plain(a)||a.schema!==A.schema||a.path!=='retail.priorReadObservations'||a.generation!==v.generation||a.sid!==v.feed.sid||a.epoch!=='roster-'+await sha256(utf8(a.kids.join(',')))||!approvedRoster(a.kids,p)||new Set(a.kids).size!==a.kids.length||a.kids.join(',')!==a.kids.slice().sort().join(',')||a.kids.join(',')!==JSON.parse(v.feed.rows['3'].body).msgs.map(m=>m.kid).sort().join(','))fail('archive manifest lineage/roster');
 if(!integer(a.fullBytes)||a.fullBytes>A.maxReconstructedBytes||!HEX.test(a.fullSha256)||!Number.isSafeInteger(a.entries)||a.entries<0||a.entries>A.maxEntries||!Array.isArray(a.chunks)||!a.chunks.length||a.chunks.length>A.maxChunks)fail('archive manifest bounds');
 const here=new URL(location);if(here.origin!==p.origin||!here.pathname.startsWith(p.basePath))fail('archive origin');
 if(typeof a.prefix!=='string'||typeof a.suffix!=='string')fail('archive exact text');const prefix=utf8(a.prefix),suffix=utf8(a.suffix);let total=prefix.length+suffix.length+2,count=0,parts=[],saved={},seen=new Set();
 for(let i=0;i<a.chunks.length;i++){
  const m=a.chunks[i];if(!exactKeys(m,['path','wireBytes','wireSha256','plainBytes','plainSha256','entries'])||!integer(m.wireBytes)||m.wireBytes>p.maxBodyBytes||!integer(m.plainBytes)||m.plainBytes>A.maxChunkPlaintextBytes||!HEX.test(m.wireSha256)||!HEX.test(m.plainSha256)||!integer(m.entries)||!new RegExp('^archives/retail-v1/[a-f0-9]{64}\\.json$').test(m.path)||seen.has(m.path))fail('archive chunk manifest');seen.add(m.path);
  const url=new URL(m.path,new URL(p.basePath,p.origin));if(url.origin!==p.origin||url.pathname!==p.basePath+m.path||url.search||url.hash)fail('archive path');
  let wire;if(cached!==null){if(typeof cached[m.path]!=='string')fail('archive offline chunk missing');wire=utf8(cached[m.path]);}else wire=await fetchBounded(url.href,{...p,maxFeedBytes:p.maxBodyBytes},fetcher);
  if(wire.length!==m.wireBytes||await sha256(wire)!==m.wireSha256)fail('archive wire integrity');
  let text;try{text=new TextDecoder('utf-8',{fatal:true}).decode(wire)}catch{fail('archive wire utf8')};const e=envelope(text,true,p);
  if(e.archiveSchema!==A.schema||e.archiveEpoch!==a.epoch||e.sid!==a.epoch+'-'+m.plainSha256||e.msgs.map(m=>m.kid).sort().join(',')!==a.kids.join(','))fail('archive chunk lineage');
  const z=await decrypt(e,p.maxPlaintextBytes);if(!exactKeys(z,['raw']))fail('archive chunk format');const raw=unbase64(z.raw);
  if(raw.length!==m.plainBytes||await sha256(raw)!==m.plainSha256)fail('archive plaintext integrity');
  let arr;try{arr=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw))}catch{fail('archive plaintext JSON')};if(!Array.isArray(arr)||arr.length!==m.entries||raw[0]!==91||raw.at(-1)!==93)fail('archive entry count');
  total+=raw.length-2+(i?1:0);count+=arr.length;if(total>A.maxReconstructedBytes||count>A.maxEntries)fail('archive reconstruction bound');parts.push(raw.slice(1,-1));saved[m.path]=text;
 }
 if(count!==a.entries||total!==a.fullBytes)fail('archive total count/length');
 const assembled=[prefix,utf8('[')];for(let i=0;i<parts.length;i++){if(i)assembled.push(utf8(','));assembled.push(parts[i]);}assembled.push(utf8(']'),suffix);const raw=concatBytes(assembled);
 if(raw.length!==a.fullBytes||await sha256(raw)!==a.fullSha256)fail('archive reconstruction hash');let data;try{data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw))}catch{fail('archive reconstruction JSON')};if(!data.snapshot||!Array.isArray(data.retail?.priorReadObservations)||data.retail.priorReadObservations.length!==a.entries)fail('archive reconstructed shape');return {data,chunks:saved};
}
