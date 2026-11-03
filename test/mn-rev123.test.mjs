// Tests for the rev123 port: Online revenue detail (Today > Online tap) always shows the
// channel split - stale reads keep their rows labelled as-of, missing reads are unknown-not-zero.
// Mirrors dj-ops-android Rev123ChannelSplitTest.kt and web commit 8e64e0d.
// Run: node test/mn-rev123.test.mjs
import assert from 'node:assert/strict';
const cl=()=>({toggle(){},add(){},remove(){},contains:()=>false});
const store=()=>({getItem:()=>null,setItem(){},removeItem(){}});
globalThis.localStorage=store();globalThis.sessionStorage=store();
const el=()=>({remove(){},content:"",clientWidth:0,innerHTML:'',textContent:'',value:'',style:{},classList:cl(),dataset:{},append(){},appendChild(){},setAttribute(){},getAttribute:()=>null,addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[],focus(){},blur(){},click(){}});
globalThis.document={documentElement:{dataset:{}},body:{classList:cl(),dataset:{},appendChild(){}},addEventListener(){},removeEventListener(){},querySelector:()=>el(),querySelectorAll:()=>[],getElementById:()=>el(),createElement:()=>el()};
globalThis.location={reload(){},href:'http://localhost/'};
globalThis.fetch=()=>Promise.reject(new Error('offline test stub'));
if(typeof globalThis.window==='undefined')globalThis.window=globalThis;
window.addEventListener=window.addEventListener||(()=>{});window.scrollTo=()=>{};
globalThis.requestAnimationFrame=()=>0;globalThis.MutationObserver=class{constructor(){}observe(){}disconnect(){}};
const T=(await import('../app.js')).__mnTest;

const IST=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
const addD=(iso,n)=>{const d=new Date(iso+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
let n=0;const ok=(name,fn)=>{fn();n++;console.log('PASS',name);};
const TODAY=IST(),YDAY=addD(TODAY,-1);

const orders=()=>[
 {id:'DJ-1',status:'Processing',amt:500,ch:'Myntra',pay:'Prepaid',ageH:1,items:[{sku:'OK-SKU',qty:2}]},
 {id:'DJ-2',status:'Shipped',amt:900,ch:'Shopify',pay:'COD',ageH:3,items:[{sku:'OK-SKU2',qty:1}]},
];
function base(over={}){
 return Object.assign({
  snapshot:{day:TODAY,revenue:9500,orderCount:2,readAt:TODAY+'T09:00:00+05:30',at:'9:00 AM'},
  orders:orders(),
  retail:{day:TODAY,status:'ok',at:'today',readAt:TODAY+'T09:05:00+05:30',stores:[]},
  history:[],retailHistory:[],
 },over);
}
function openRev(d){T.set(d);T.detail('r:rev');return T.revDetail();}

// --- fresh read: unchanged behaviour ---
ok('fresh: revenue detail unchanged, no stale labels',()=>{
 const h=openRev(base({snapshot:{day:TODAY,revenue:9500,orderCount:2,readAt:TODAY+'T09:00:00+05:30',at:'9:00 AM',
  channelsToday:{orders:2,by:[{ch:'Myntra',rev:9500,orders:2}]}}}));
 assert.ok(!h.includes('Not read for today'),'no stale banner');
 assert.ok(h.includes('Revenue so far'),'fresh revenue label');
 assert.ok(h.includes('<h2>By channel</h2>'),'plain channel header');
 assert.ok(h.includes('Myntra'),'channel row');
 assert.equal(T.title(),'Revenue today','fresh title');
});

// --- stale read: card + rows stay, labelled as-of, never hidden ---
ok('stale: split rows render under as-of header, revenue marked (last read)',()=>{
 const h=openRev(base({snapshot:{day:YDAY,revenue:9500,orderCount:2,readAt:YDAY+'T21:00:00+05:30',at:'9:00 PM',
  channelsToday:{orders:2,by:[{ch:'Myntra',rev:9500,orders:2}]}}}));
 assert.ok(!h.includes('Older readings are not revenue'),'old hide behaviour gone');
 assert.ok(h.includes('Not read for today'),'stale banner');
 assert.ok(h.includes('Revenue (last read)'),'revenue labelled last read');
 assert.ok(h.includes('By channel · as of last read'),'as-of channel header');
 assert.ok(h.includes('Myntra'),'channel rows still rendered');
 assert.ok(h.includes('as of '+YDAY),'as-of day named');
 assert.ok(h.includes('Latest orders'),'orders still below');
 assert.equal(T.title(),'Revenue · last read','stale title');
});

// --- missing channel read: unknown, not zero ---
ok('missing: no channel source renders unknown-not-zero, never hidden',()=>{
 const h=openRev(base({snapshot:{day:TODAY,revenue:0,orderCount:0,readAt:TODAY+'T09:00:00+05:30',at:'9:00 AM'},orders:[]}));
 assert.ok(h.includes('unknown, not zero'),'unknown-not-zero note');
 assert.ok(!h.includes('Older readings are not revenue'),'not hidden');
});

// --- stale + missing: both notes, still not hidden ---
ok('stale+missing: stale banner and unknown-not-zero together',()=>{
 const h=openRev(base({snapshot:{day:YDAY,revenue:0,orderCount:0,readAt:YDAY+'T21:00:00+05:30'},orders:[]}));
 assert.ok(h.includes('Not read for today'),'stale banner');
 assert.ok(h.includes("Today's channel split is unknown, not zero"),'banner names unknown split');
 assert.ok(h.includes('Channel split is not supplied in this read'),'empty split note');
});

// --- ordering: revenue desc, Not itemised last ---
ok('order: channels sorted by revenue desc, Not itemised last',()=>{
 const h=openRev(base({snapshot:{day:TODAY,revenue:20000,orderCount:5,readAt:TODAY+'T09:00:00+05:30',at:'9:00 AM',
  channelsToday:{orders:5,by:[{ch:'Nykaa',rev:2000,orders:1},{ch:'Not itemised',rev:9000,orders:2},{ch:'Myntra',rev:6000,orders:2},{ch:'Shopify',rev:3000,orders:1}]}}}));
 const iNy=h.indexOf('>Nykaa<'),iMy=h.indexOf('>Myntra<'),iSh=h.indexOf('>Shopify<'),iNi=h.indexOf('>Not itemised<');
 assert.ok(iMy>-1&&iSh>iMy&&iNy>iSh,'revenue desc: Myntra > Shopify > Nykaa');
 assert.ok(iNi>iNy,'Not itemised last');
});

// --- per-channel drill unchanged ---
ok('drill: channel rows keep data-d taps, Not itemised not tappable',()=>{
 const h=openRev(base({snapshot:{day:TODAY,revenue:9500,orderCount:3,readAt:TODAY+'T09:00:00+05:30',at:'9:00 AM',
  channelsToday:{orders:3,by:[{ch:'Myntra',rev:9500,orders:2},{ch:'Not itemised',rev:500,orders:1}]}}}));
 assert.ok(h.includes('data-d="c:Myntra"'),'channel drill intact');
 assert.ok(!h.includes('data-d="c:Not itemised"'),'Not itemised not tappable');
});

console.log('mn-rev123: ALL PASS ('+n+')');
process.exit(0);
