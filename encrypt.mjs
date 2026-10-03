// Used by the hourly refresh job. Needs only PUBLIC keys. Usage: node encrypt.mjs data.json pubkeys.json > payload.json
import {readFileSync} from 'node:fs';import {webcrypto as c,createHash} from 'node:crypto';
const [,, dataPath,keysPath]=process.argv;const data=readFileSync(dataPath);const keys=JSON.parse(readFileSync(keysPath));
const b64=u=>Buffer.from(u).toString('base64');const msgs=[];
// v2: data encrypted once with a random AES key; that key is wrapped per recipient. Size barely grows with the number of keys.
const dk=c.getRandomValues(new Uint8Array(32));const div=c.getRandomValues(new Uint8Array(12));
const dkey=await c.subtle.importKey('raw',dk,'AES-GCM',false,['encrypt']);
const dct=await c.subtle.encrypt({name:'AES-GCM',iv:div},dkey,data);
for(const pub of keys){
 const kid=b64(createHash('sha256').update(pub.x+pub.y).digest()).slice(0,8).replace(/[+/=]/g,'x');
 const eph=await c.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
 const rpk=await c.subtle.importKey('jwk',{kty:'EC',crv:'P-256',x:pub.x,y:pub.y},{name:'ECDH',namedCurve:'P-256'},false,[]);
 const bits=await c.subtle.deriveBits({name:'ECDH',public:rpk},eph.privateKey,256);
 const hk=await c.subtle.importKey('raw',bits,'HKDF',false,['deriveKey']);
 const key=await c.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:new Uint8Array(0),info:new TextEncoder().encode('djops-v1')},hk,{name:'AES-GCM',length:256},false,['encrypt']);
 const iv=c.getRandomValues(new Uint8Array(12));const wk=await c.subtle.encrypt({name:'AES-GCM',iv},key,dk);
 const e=await c.subtle.exportKey('jwk',eph.publicKey);msgs.push({kid,epk:{x:e.x,y:e.y},iv:b64(iv),wk:b64(wk)});}
process.stdout.write(JSON.stringify({v:2,iv:b64(div),ct:b64(dct),msgs}));
