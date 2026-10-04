const enc=new TextEncoder(),dec=new TextDecoder();
const b64=u=>btoa(String.fromCharCode(...new Uint8Array(u)));
const ub64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
async function pbkdf(pass,salt){const k=await crypto.subtle.importKey('raw',enc.encode(pass),'PBKDF2',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:600000,hash:'SHA-256'},k,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);}
export async function kid(pubJwk){const d=await crypto.subtle.digest('SHA-256',enc.encode(pubJwk.x+pubJwk.y));return b64(d).slice(0,8).replace(/[+/=]/g,'x');}
export async function setup(pass){
 const kp=await crypto.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
 const priv=await crypto.subtle.exportKey('jwk',kp.privateKey),pub=await crypto.subtle.exportKey('jwk',kp.publicKey);
 const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
 const ct=await crypto.subtle.encrypt({name:'AES-GCM',iv},await pbkdf(pass,salt),enc.encode(JSON.stringify(priv)));
 const pubS={kty:'EC',crv:'P-256',x:pub.x,y:pub.y};
 return {vault:{salt:b64(salt),iv:b64(iv),ct:b64(ct),pub:pubS},pubText:JSON.stringify(pubS)};}
export async function unlock(vault,pass){
 const pt=await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(vault.iv)},await pbkdf(pass,ub64(vault.salt)),ub64(vault.ct));
 return crypto.subtle.importKey('jwk',JSON.parse(dec.decode(pt)),{name:'ECDH',namedCurve:'P-256'},false,['deriveBits']);}
async function inflate(buf){const r=new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream('gzip')));return new Uint8Array(await r.arrayBuffer())}
async function toText(payload,bytes){return dec.decode(payload.z?await inflate(bytes):bytes)}
export async function decryptPayload(payload,privKey,myKid){
 const m=payload.msgs.find(x=>x.kid===myKid);if(!m)throw new Error('This update was not encrypted for this phone');
 const epk=await crypto.subtle.importKey('jwk',{kty:'EC',crv:'P-256',x:m.epk.x,y:m.epk.y},{name:'ECDH',namedCurve:'P-256'},false,[]);
 const bits=await crypto.subtle.deriveBits({name:'ECDH',public:epk},privKey,256);
 const hk=await crypto.subtle.importKey('raw',bits,'HKDF',false,['deriveKey']);
 const key=await crypto.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:new Uint8Array(0),info:enc.encode('djops-v1')},hk,{name:'AES-GCM',length:256},false,['decrypt']);
 if(payload.v===2){const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(m.iv)},key,ub64(m.wk));
  const dkey=await crypto.subtle.importKey('raw',raw,'AES-GCM',false,['decrypt']);
  return JSON.parse(await toText(payload,new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(payload.iv)},dkey,ub64(payload.ct)))));}
 const pt=await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(m.iv)},key,ub64(m.ct));
 return JSON.parse(await toText(payload,new Uint8Array(pt)));}

export async function unlockJwk(vault,pass){const pt=await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(vault.iv)},await pbkdf(pass,ub64(vault.salt)),ub64(vault.ct));return dec.decode(pt);}
export function importPriv(jwkText){return crypto.subtle.importKey('jwk',JSON.parse(jwkText),{name:'ECDH',namedCurve:'P-256'},false,['deriveBits']);}
export async function wrapWith(raw32,text){const k=await crypto.subtle.importKey('raw',raw32,'AES-GCM',false,['encrypt']);const iv=crypto.getRandomValues(new Uint8Array(12));return {iv:b64(iv),ct:b64(await crypto.subtle.encrypt({name:'AES-GCM',iv},k,enc.encode(text)))};}
export async function unwrapWith(raw32,w){const k=await crypto.subtle.importKey('raw',raw32,'AES-GCM',false,['decrypt']);return dec.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(w.iv)},k,ub64(w.ct)));}
export const rand=n=>crypto.getRandomValues(new Uint8Array(n));export {b64,ub64};
