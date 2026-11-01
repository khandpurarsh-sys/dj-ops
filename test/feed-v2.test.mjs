// feed-v2 static feed loader gates. Run: node test/feed-v2.test.mjs (no deps, Node 22+)
import {readFileSync, writeFileSync, mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {webcrypto as wc, createHash} from 'node:crypto';

const REPO='owner/repo';
const appSrc=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const block=appSrc.slice(appSrc.indexOf('/*FEEDV2 START'),appSrc.indexOf('/*FEEDV2 END*/'));
const cryptoUrl=pathToFileURL(join(process.cwd(),'crypto.js')).href;

const prelude=`
import {decryptPayload} from ${JSON.stringify(cryptoUrl)};
const LS={store:{},quota:false,getItem(k){return k in this.store?this.store[k]:null},setItem(k,v){if(this.quota)throw new Error('quota');this.store[k]=String(v)}};
const window={DJ_CONFIG:{repo:${JSON.stringify(REPO)}}};
function feedSave(k,v){try{LS.setItem(k,v);return true}catch{return false}}
const feedUrl=n=>{const b=(window.DJ_CONFIG||{}).feedBase;return b?new URL(n,b).href:n};
let staticFeed=null,feedTransport='',priv=null,myKid=null;
`;
const src=prelude+block+`
export {staticFeedV2Read,readFeedV2,LS};
export const __get=()=>({staticFeed,feedTransport});
export const __set=(k,v)=>{if(k==='priv')priv=v;else if(k==='myKid')myKid=v;};
`;
const tmp=mkdtempSync(join(tmpdir(),'feedv2-'));
writeFileSync(join(tmp,'gen.mjs'),src);
const M=await import(pathToFileURL(join(tmp,'gen.mjs')).href);
const {setup,unlock,kid}=await import(cryptoUrl);

const b64=u=>Buffer.from(u).toString('base64');
const shaHex=t=>createHash('sha256').update(t).digest('hex');

// vault A = this phone, vault B = someone else (decrypt-failure gate)
const PASS='test-pass-123';
const vA=await setup(PASS),vB=await setup(PASS);
const privA=await unlock(vA.vault,PASS), kidA=await kid(vA.vault.pub);

async function envelope(data,pub,sid,slim){
 const raw=new TextEncoder().encode(JSON.stringify(data));
 const dk=wc.getRandomValues(new Uint8Array(32)),div=wc.getRandomValues(new Uint8Array(12));
 const dkey=await wc.subtle.importKey('raw',dk,'AES-GCM',false,['encrypt']);
 const dct=await wc.subtle.encrypt({name:'AES-GCM',iv:div},dkey,raw);
 const eph=await wc.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
 const rpk=await wc.subtle.importKey('jwk',{kty:'EC',crv:'P-256',x:pub.x,y:pub.y},{name:'ECDH',namedCurve:'P-256'},false,[]);
 const bits=await wc.subtle.deriveBits({name:'ECDH',public:rpk},eph.privateKey,256);
 const hk=await wc.subtle.importKey('raw',bits,'HKDF',false,['deriveKey']);
 const key=await wc.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:new Uint8Array(0),info:new TextEncoder().encode('djops-v1')},hk,{name:'AES-GCM',length:256},false,['encrypt']);
 const iv=wc.getRandomValues(new Uint8Array(12));
 const wk=await wc.subtle.encrypt({name:'AES-GCM',iv},key,dk);
 const e=await wc.subtle.exportKey('jwk',eph.publicKey);
 return JSON.stringify({v:2,iv:b64(div),ct:b64(dct),msgs:[{kid:await kid(pub),epk:{x:e.x,y:e.y},iv:b64(iv),wk:b64(wk)}],sid,slim});
}
async function feed({gen=1,prev=null,repo=REPO,sid='SID-1',pub=vA.vault.pub,policyVersion='2026-11-draft',dropKey=null,extraKey=null,tamperHash=false,tamperLen=false}={}){
 const data={snapshot:{revenue:1,at:'2026-11-01T10:00:00+05:30'}};
 const slimBody=await envelope(data,pub,sid,true), fullBody=await envelope(data,pub,sid,false);
 const rows={};
 for(const [k,body] of Object.entries({'1':slimBody,'2':slimBody,'3':fullBody,'87':slimBody,'88':slimBody}))
  rows[k]={body,sha256:shaHex(body),byteLength:new TextEncoder().encode(body).length};
 if(dropKey)delete rows[dropKey];
 if(extraKey)rows[extraKey]={...rows['1']};
 if(tamperHash)rows['1'].sha256='0'.repeat(64);
 if(tamperLen)rows['1'].byteLength=rows['1'].byteLength+1;
 return {version:2,repo,generation:gen,previous:prev,policyVersion,sid,rows};
}
function mockFetch(text,{status=200,stream=false}={}){
 globalThis.fetch=async()=>{
  if(status!==200)return {ok:false,status,body:null,text:async()=>''};
  if(stream){
   const bytes=new TextEncoder().encode(text);let off=0;
   return {ok:true,status,body:{getReader:()=>({read:async()=>{if(off>=bytes.length)return{done:true};const c=bytes.slice(off,off+65536);off+=c.length;return{done:false,value:c}},cancel:async()=>{}})}};
  }
  return {ok:true,status,body:null,text:async()=>text};
 };
}
let pass=0,fail=0;
const t=(n,ok)=>{if(ok){pass++;console.log('ok:',n)}else{fail++;console.log('FAIL:',n)}};
const throws=async(n,fn,re)=>{try{await fn();fail++;console.log('FAIL (no throw):',n)}catch(e){const ok=re.test(e.message);if(ok){pass++;console.log('ok:',n)}else{fail++;console.log('FAIL ('+e.message+'):',n)}}};

function reset(){M.LS.store={};M.LS.quota=false;M.__set('priv',privA);M.__set('myKid',kidA);}

// 1. genesis accept
reset();let f=await feed({gen:1,prev:null});mockFetch(JSON.stringify(f),{stream:true});
await M.staticFeedV2Read();
t('genesis accepted',M.__get().staticFeed&&M.__get().staticFeed.generation===1&&M.readFeedV2().generation===1);
// 2. idempotent same bytes
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:shaHex(JSON.stringify(f)),sid:'SID-1'});
mockFetch(JSON.stringify(f),{stream:true});
await M.staticFeedV2Read();
t('same generation same bytes idempotent',M.__get().staticFeed.generation===1);
// 3. replay: older generation rejected
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:2,feedSHA:'x',sid:'SID-1'});
mockFetch(JSON.stringify(f));
await throws('older generation rejected',()=>M.staticFeedV2Read(),/older/);
// 4. conflict: same generation different bytes
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:'deadbeef',sid:'SID-1'});
mockFetch(JSON.stringify(f));
await throws('same generation different bytes rejected',()=>M.staticFeedV2Read(),/conflicts/);
// 5. skipped generations allowed
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:2,feedSHA:'x',sid:'SID-1'});
const f4=await feed({gen:4,prev:shaHex('gen3')});mockFetch(JSON.stringify(f4));
await M.staticFeedV2Read();
t('skipped generation accepted',M.readFeedV2().generation===4);
// 6. wrong repo
reset();const fr=await feed({gen:1,prev:null,repo:'evil/repo'});mockFetch(JSON.stringify(fr));
await throws('wrong repo rejected',()=>M.staticFeedV2Read(),/format invalid/);
// 7. row keys must be exact
reset();const fd=await feed({gen:1,prev:null,dropKey:'88'});mockFetch(JSON.stringify(fd));
await throws('missing row rejected',()=>M.staticFeedV2Read(),/exactly/);
const fe=await feed({gen:1,prev:null,extraKey:'9'});mockFetch(JSON.stringify(fe));
await throws('extra row rejected',()=>M.staticFeedV2Read(),/exactly/);
// 8. hash mismatch
reset();const fh=await feed({gen:1,prev:null,tamperHash:true});mockFetch(JSON.stringify(fh));
await throws('hash mismatch rejected',()=>M.staticFeedV2Read(),/hash mismatch/);
// 9. byteLength mismatch
reset();const fl=await feed({gen:1,prev:null,tamperLen:true});mockFetch(JSON.stringify(fl));
await throws('byteLength mismatch rejected',()=>M.staticFeedV2Read(),/length mismatch/);
// 10. sid mismatch
reset();const fs=await feed({gen:1,prev:null});fs.sid='OTHER';mockFetch(JSON.stringify(fs));
await throws('sid mismatch rejected',()=>M.staticFeedV2Read(),/snapshots mismatch/);
// 11. malformed json
reset();mockFetch('{not json');
await throws('malformed rejected',()=>M.staticFeedV2Read(),/malformed/);
// 12. decrypt failure: high-water not pinned
reset();const fb=await feed({gen:1,prev:null,pub:vB.vault.pub});mockFetch(JSON.stringify(fb));
await throws('undecryptable rejected',()=>M.staticFeedV2Read(),/decrypt failed/);
t('high-water not pinned on decrypt failure',M.readFeedV2()===null);
// 13. quota
reset();M.LS.quota=true;mockFetch(JSON.stringify(await feed({gen:1,prev:null})));
await throws('quota rejected',()=>M.staticFeedV2Read(),/Cannot save/);
// 14. genesis must carry null previous; later generations must carry one
reset();const fp=await feed({gen:1,prev:'abc'.padEnd(64,'0')});mockFetch(JSON.stringify(fp));
await throws('genesis with previous rejected',()=>M.staticFeedV2Read(),/genesis/);
const fp2=await feed({gen:2,prev:null});mockFetch(JSON.stringify(fp2));
await throws('later generation without previous rejected',()=>M.staticFeedV2Read(),/previous missing/);
// 15. policyVersion presence/type only
reset();const fv=await feed({gen:1,prev:null});delete fv.policyVersion;mockFetch(JSON.stringify(fv));
await throws('missing policyVersion rejected',()=>M.staticFeedV2Read(),/policyVersion/);
// 16. oversized response
reset();const big=JSON.stringify(await feed({gen:1,prev:null}));const pad=' '.repeat(2*1024*1024);
mockFetch(big.slice(0,-1)+',"pad":"'+pad+'"}',{stream:true});
await throws('oversized response rejected',()=>M.staticFeedV2Read(),/too large/);
// 17. pre-cutover: 404 with no high-water leaves fallback possible; post-accept it is fatal upstream
reset();mockFetch('',{status:404});
await throws('404 surfaces',()=>M.staticFeedV2Read(),/HTTP 404/);
t('no high-water after 404 (v1 fallback allowed)',M.readFeedV2()===null);
M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:'x',sid:'s'});
t('high-water present after prior accept (v1 fallback forbidden)',M.readFeedV2()!==null);

// 19. gen2 object previous accepted when chained to accepted gen1
reset();const g1=await feed({gen:1,prev:null});const g1text=JSON.stringify(g1);
mockFetch(g1text);await M.staticFeedV2Read();
const g2=await feed({gen:2,prev:{generation:1,sha256:shaHex(g1text)}});mockFetch(JSON.stringify(g2));
await M.staticFeedV2Read();
t('gen2 object previous accepted',M.readFeedV2().generation===2);
// 20. object previous with wrong sha256 rejected
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:shaHex(g1text),sid:'SID-1'});
const g2b=await feed({gen:2,prev:{generation:1,sha256:'f'.repeat(64)}});mockFetch(JSON.stringify(g2b));
await throws('object previous wrong sha rejected',()=>M.staticFeedV2Read(),/previous hash does not match/);
// 21. object previous generation must be gen-1
reset();const g2c=await feed({gen:2,prev:{generation:5,sha256:'f'.repeat(64)}});mockFetch(JSON.stringify(g2c));
await throws('object previous generation mismatch rejected',()=>M.staticFeedV2Read(),/previous generation mismatch/);
// 22. string previous adjacent generation validated against high-water
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:shaHex(g1text),sid:'SID-1'});
const g2d=await feed({gen:2,prev:shaHex(g1text)});mockFetch(JSON.stringify(g2d));
await M.staticFeedV2Read();
t('string previous adjacent accepted',M.readFeedV2().generation===2);
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:shaHex(g1text),sid:'SID-1'});
const g2e=await feed({gen:2,prev:'e'.repeat(64)});mockFetch(JSON.stringify(g2e));
await throws('string previous adjacent wrong hash rejected',()=>M.staticFeedV2Read(),/previous hash does not match/);
// 23. skipped generation with object previous beyond high-water still allowed
reset();M.LS.store['dj_feed_v2']=JSON.stringify({repo:REPO,generation:1,feedSHA:shaHex(g1text),sid:'SID-1'});
const g4=await feed({gen:4,prev:{generation:3,sha256:'c'.repeat(64)}});mockFetch(JSON.stringify(g4));
await M.staticFeedV2Read();
t('skip with object previous allowed',M.readFeedV2().generation===4);

// 18. source wiring: prepareFeed guard, sw.js no-store rule, crypto decompressed cap
t('prepareFeed fatal post-accept',/if\(readFeedV2\(\)\)throw e2/.test(appSrc));
const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
t('sw.js no-store covers feed-v2.json',sw.includes("endsWith('/feed-v2.json')"));
const cjs=readFileSync(new URL('../crypto.js',import.meta.url),'utf8');
t('decompressed 8 MiB cap',cjs.includes('8388608'));

console.log(fail?fail+' FAILURES ('+pass+' ok)':'ALL PASS ('+pass+')');
process.exit(fail?1:0);
