// Tests for the rev122 port: Orders sort/filter chip+dialog, Best sellers period x channel matrix.
// Run: node test/mn-rev122.test.mjs
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
 {id:'1001',status:'Shipped',amt:500,ch:'Shopify',items:[{sku:'DJ-AAA-BLK-M',qty:1}]},
 {id:'1002',status:'Processing',amt:1500,ch:'Myntra',items:[{sku:'DJ-BBB-BLU-L',qty:2},{sku:'DJ-CCC-GRN-S',qty:1}]},
 {id:'1003',status:'Processing',amt:900,ch:'Shopify',items:[{sku:'DJ-AAA-BLK-M',qty:1}]},
 {id:'1004',status:'Cancelled',amt:2000,ch:'Ajio',items:[{sku:'DJ-DDD-RED-XL',qty:3}]},
 {id:'1005',status:'Complete',amt:300,ch:'Shopify',items:[{sku:'DJ-EEE-WHT-M',qty:1}]},
];
function base(over={}){
 return Object.assign({
  snapshot:{day:TODAY,revenue:4200,orderCount:4,readAt:new Date().toISOString()},
  orders:orders(),
  retail:{day:TODAY,status:'ok',at:'today',readAt:new Date().toISOString(),stores:[{name:'PTG',sales:3000,bills:2,units:3,billList:[
    {no:'R-1',items:[{sku:'DJ-AAA-BLK-M',qty:2,amt:1000},{sku:'DJ-FFF-PNK-S',qty:-1,amt:-500}]},
    {no:'R-2',items:[{sku:'DJ-GGG-GRY-L',qty:1,amt:800}]},
  ]}]},
  history:[],retailHistory:[],
  retail7:[{sku:'DJ-AAA-BLK-M',qty:5,amt:5000},{sku:'DJ-HHH-NAV-L',qty:3,amt:2400}],
  retail30:[{sku:'DJ-AAA-BLK-M',qty:9,amt:9000}],
  sellers:{week:[{sku:'DJ-BBB-BLU-L',qty:7,rev:null}],month:[{sku:'DJ-BBB-BLU-L',qty:11,rev:4000}],quarter:[{sku:'DJ-BBB-BLU-L',qty:20,rev:8000}]},
  retail7AsOf:new Date().toISOString(),retail30AsOf:new Date().toISOString(),sellersAsOf:new Date().toISOString(),
 },over);
}

// --- Orders: inline chip, no FAB ---
ok('orders: inline sort chip in chips row, FAB gone',()=>{
 T.set(base());T.sheet(false);T.sort('new','All');
 const h=T.mnOrders();
 assert.ok(h.includes('mn-schip'),'inline chip class');
 assert.ok(h.includes('data-mn="sheet:open"'),'chip opens dialog');
 assert.ok(!h.includes('mn-fab'),'FAB removed');
 assert.ok(h.indexOf('mn-schip')>h.indexOf('mn-chips'),'chip inside chips row');
});
ok('orders: window-level dialog, not bottom sheet',()=>{
 T.set(base());T.sheet(true);
 const h=T.mnOrders();
 assert.ok(h.includes('mn-dialog'),'dialog rendered');
 assert.ok(!h.includes('mn-sheet"'),'no bottom sheet');
 assert.ok(h.includes('aria-modal="true"'),'modal dialog');
 for(const l of ['Newest first','Highest value','Oldest first','All channels'])assert.ok(h.includes(l),'option '+l);
 assert.ok(h.includes('>Done<'),'done button');
 T.sheet(false);
});
ok('orders: sort within status groups, spec group order',()=>{
 T.set(base());T.sort('high','All');
 const h=T.mnOrders();
 const iP=h.indexOf('Processing'),iS=h.indexOf('Shipped'),iC=h.indexOf('Complete'),iX=h.indexOf('Cancelled');
 assert.ok(iP>-1&&iS>-1&&iC>-1&&iX>-1,'all groups present');
 assert.ok(iP<iS&&iS<iC&&iC<iX,'group order Processing<Shipped<Complete<Cancelled');
 const hi=h.indexOf('1502'),lo=h.indexOf('1003');
 assert.ok(h.indexOf('#1002')<h.indexOf('#1003'),'highest value first within Processing');
 T.sort('new','All');
});
ok('orders: pay filter applies',()=>{
 T.set(base());T.sort('new','Prepaid');
 const h=T.mnOrders();
 assert.ok(!h.includes('mn-grp'),'no groups when nothing is Prepaid');
 T.sort('new','All');
});

// --- Sellers matrix ---
ok('sellers: tabs and period chips render',()=>{
 T.set(base());T.best('retail','today');
 const h=T.mnBest();
 for(const l of ['Retail','Online','Combined','Today','7D','30D','90D'])assert.ok(h.includes(l),'control '+l);
 assert.ok(h.includes('data-mn="bch:combined"')&&h.includes('data-mn="brg:90"'),'mn actions');
});
ok('sellers: retail 7D uses retail7, ranked by signed units',()=>{
 T.set(base());T.best('retail','7');
 const h=T.mnBest();
 assert.ok(h.includes('Retail · 7-day report'),'label');
 assert.ok(h.includes('5 units'),'retail7 qty shown');
 assert.ok(!h.includes('DJ-BBB-BLU-L'),'online week not mixed in');
 assert.ok(h.indexOf('DJ-AAA-BLK-M')<h.indexOf('DJ-HHH-NAV-L'),'ranked by units');
});
ok('sellers: online 7D uses sellers.week, never retail7 (bug fix)',()=>{
 T.set(base());T.best('online','7');
 const h=T.mnBest();
 assert.ok(h.includes('Online · 7-day report'),'label');
 assert.ok(h.includes('DJ-BBB-BLU-L'),'online row present');
 assert.ok(!h.includes('DJ-HHH-NAV-L'),'retail7 not shown on online tab');
 assert.ok(h.includes('Revenue not supplied'),'null rev labelled');
});
ok('sellers: retail 90D not supplied, unknown not zero',()=>{
 T.set(base());T.best('retail','90');
 const h=T.mnBest();
 assert.ok(h.includes('Retail 90-day product data is not supplied in this feed. Unknown, not zero.'),'90D message');
 assert.ok(h.includes('Other ranges remain available'),'ranges hint');
});
ok('sellers: range label shows asOf stamp, else unavailable',()=>{
 T.set(base());T.best('online','30');
 let h=T.mnBest();
 assert.ok(h.includes('may be stale'),'stale wording');
 T.set(base({sellersAsOf:null}));
 h=T.mnBest();
 assert.ok(h.includes('Range-report read time unavailable'),'missing stamp wording');
});
ok('sellers: today online from current-day lines, cancelled excluded, units only',()=>{
 T.set(base());T.best('online','today');
 const h=T.mnBest();
 assert.ok(h.includes('DJ-AAA-BLK-M'),'today line present');
 assert.ok(!h.includes('DJ-DDD-RED-XL'),'cancelled order items excluded');
 assert.ok(!h.includes('₹'),'no revenue shown for online today');
});
ok('sellers: unread today shows notes, not lines',()=>{
 T.set(base({snapshot:{day:YDAY,revenue:100,readAt:new Date().toISOString()},retail:{day:YDAY,status:'ok',at:'y',stores:[]}}));
 T.best('online','today');
 let h=T.mnBest();
 assert.ok(h.includes('No orders read yet for'),'online gate note');
 assert.ok(!h.includes('DJ-AAA-BLK-M'),'no stale online lines');
 T.best('retail','today');
 h=T.mnBest();
 assert.ok(h.includes('0 bills read for'),'retail gate note');
 assert.ok(!h.includes('DJ-GGG-GRY-L'),'no stale retail lines');
});
ok('sellers: retail today signed units, returns negative',()=>{
 T.set(base());T.best('retail','today');
 const h=T.mnBest();
 assert.ok(h.includes('-1 units')||h.includes('−1'),'negative return shown signed');
});
ok('sellers: combined shows both source-labelled groups, no sums',()=>{
 T.set(base());T.best('combined','7');
 const h=T.mnBest();
 assert.ok(h.includes('Retail · 7-day report')&&h.includes('Online · 7-day report'),'both sections');
 assert.ok(h.includes('DJ-AAA-BLK-M')&&h.includes('DJ-BBB-BLU-L'),'both sources');
 assert.ok(h.includes('Retail units')&&h.includes('Online units'),'combined KPI chips');
});
ok('sellers: channel split donut kept',()=>{
 T.set(base());T.best('retail','today');
 const h=T.mnBest();
 assert.ok(h.includes('Channel split'),'donut section');
});
console.log('ALL PASS ('+n+')');
process.exit(0);
