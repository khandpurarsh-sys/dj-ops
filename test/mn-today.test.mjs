// Tests for the mn* Today-port functions. Run: node test/mn-today.test.mjs
import assert from 'node:assert/strict';

// --- minimal DOM/browser stubs so app.js (a browser module) imports in node ---
const cl=()=>({toggle(){},add(){},remove(){},contains:()=>false});
const store=()=>({getItem:()=>null,setItem(){},removeItem(){}});
globalThis.localStorage=store();
globalThis.sessionStorage=store();
const el=()=>({remove(){},content:"",clientWidth:0,innerHTML:'',textContent:'',value:'',style:{},classList:cl(),dataset:{},append(){},appendChild(){},setAttribute(){},getAttribute:()=>null,addEventListener(){},querySelector:()=>null,querySelectorAll:()=>[],focus(){},blur(){},click(){}});
globalThis.document={documentElement:{dataset:{}},body:{classList:cl(),dataset:{},appendChild(){}},addEventListener(){},removeEventListener(){},querySelector:()=>el(),querySelectorAll:()=>[],getElementById:()=>el(),createElement:()=>el()};
globalThis.location={reload(){},href:'http://localhost/'};
globalThis.fetch=()=>Promise.reject(new Error('offline test stub'));
if(typeof globalThis.window==='undefined')globalThis.window=globalThis;
window.addEventListener=window.addEventListener||(()=>{});
window.scrollTo=()=>{};
globalThis.requestAnimationFrame=()=>0;
globalThis.MutationObserver=class{constructor(){}observe(){}disconnect(){}};

const T=(await import('../app.js')).__mnTest;

// --- helpers ---
const IST=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
const addD=(iso,n)=>{const d=new Date(iso+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
const nowH=()=>Number(new Date().toLocaleString('en-US',{timeZone:'Asia/Kolkata',hour:'numeric',hour12:false}))%24;
const LBL=iso=>new Date(iso+'T00:00:00+05:30').toLocaleDateString('en-IN',{day:'numeric',month:'short',timeZone:'Asia/Kolkata'});
function base(over={}){
  const d={snapshot:{day:IST(),revenue:5000,orderCount:2,readAt:new Date().toISOString()},
    orders:[],
    retail:{day:IST(),status:'ok',at:'2 Nov, 5:00 PM',stores:[{name:'PTG',sales:3000,bills:2,units:3,billList:[]}]},
    history:[],retailHistory:[]};
  return Object.assign(d,over);
}

let n=0;const ok=(name,fn)=>{fn();n++;console.log('PASS',name);};
const TODAY=IST(),YDAY=addD(TODAY,-1),FUT=addD(TODAY,3);

// 1. mnDayState: future feed day is never treated as today
ok('dayState future day -> undated',()=>{
  T.set(base({snapshot:{day:FUT,revenue:100,readAt:new Date().toISOString()}}));
  const ds=T.mnDayState();
  assert.equal(ds.onSt,'undated');
});
ok('dayState both future -> bothUndated, neutral title, refDay not future',()=>{
  T.set(base({snapshot:{day:FUT,revenue:100,readAt:new Date().toISOString()},retail:{day:FUT,status:'ok',stores:[{name:'PTG',sales:3000,bills:2,units:3,billList:[]}]}}));
  const ds=T.mnDayState();
  assert.equal(ds.onSt,'undated');assert.equal(ds.rtSt,'undated');
  assert.equal(ds.bothUndated,true);assert.equal(ds.title,'Overview');
  assert.notEqual(ds.refDay,FUT);
});
ok('dayState today/stale/undated basics',()=>{
  T.set(base());
  let ds=T.mnDayState();
  assert.equal(ds.onSt,'today');assert.equal(ds.rtSt,'today');assert.equal(ds.title,"Today's Overview");
  T.set(base({snapshot:{day:YDAY,revenue:100,readAt:new Date().toISOString()}}));
  ds=T.mnDayState();
  assert.equal(ds.onSt,'stale');assert.equal(ds.rtSt,'today');assert.equal(ds.title,"Today's Overview");
});

// 2. mnTodayHourly: observedThroughHour truncation (feed source clock)
ok('todayHourly truncates at observedThroughHour',()=>{
  const oth=Math.max(0,nowH()-3);
  const TH=[];for(let h=0;h<=23;h++)TH.push({h,rev:100});
  T.set(base({snapshot:{day:TODAY,revenue:1500,readAt:new Date().toISOString(),todayHourlyOnline:TH,todayHourlyOnlineProv:{day:TODAY,observedThroughHour:oth}}}));
  const hr=T.mnTodayHourly();
  assert.equal(hr.feed,true);
  let last=-1;hr.cum.forEach((p,h)=>{if(p&&p.v!=null)last=h;});
  assert.equal(last,oth,'series must end at observedThroughHour '+oth+', got '+last);
  assert.ok(hr.cum.slice(oth+1).every(p=>p==null),'no points beyond observedThroughHour');
});
ok('todayHourly empty feed never throws',()=>{
  T.set(base({snapshot:{day:TODAY,revenue:0,orderCount:0,readAt:new Date().toISOString()},retail:{day:TODAY,status:'ok',stores:[]}}));
  const hr=T.mnTodayHourly();
  assert.equal(hr.empty,true);assert.equal(hr.cum.length,24);
});
ok('todayHourly returns per-source series',()=>{
  const oth=nowH();
  const pts=[];for(let h=0;h<=oth;h++)pts.push({h,rev:100});
  T.set(base({snapshot:{day:TODAY,revenue:1500,readAt:new Date().toISOString(),todayHourlyOnline:pts,todayHourlyOnlineProv:{day:TODAY,observedThroughHour:oth}},
    retail:{day:TODAY,status:'ok',stores:[{name:'PTG',sales:300,bills:1,units:1,billList:[{no:'R-1',amt:300,_ms:Date.now(),items:[{qty:1}]}]}]}}));
  const hr=T.mnTodayHourly();
  assert.ok(hr.cumOn,'online series present');
  assert.ok(hr.cumRt,'retail series present (bill times derived)');
  const lastC=hr.cum.filter(p=>p&&p.v!=null).pop().v;
  const lastO=hr.cumOn.filter(p=>p&&p.v!=null).pop().v;
  const lastR=hr.cumRt.filter(p=>p&&p.v!=null).pop().v;
  assert.equal(lastC,lastO+lastR,'combined = online + retail at the last point');
});

// 3. mnYesterdayHourly: spec key variants
ok('yesterday: {h,rev} under snapshot',()=>{
  const hh=nowH();
  T.set(base({snapshot:{day:TODAY,revenue:100,readAt:new Date().toISOString(),yesterdayHourlyOnline:[{h:0,rev:200},{h:hh,rev:300}],yesterdayHourlyOnlineProv:{day:YDAY}}}));
  const y=T.mnYesterdayHourly(TODAY);
  assert.equal(y.cum[0],hh===0?500:200);assert.equal(y.cum[hh],500);
});
ok('yesterday: plain 24-number array, top-level',()=>{
  const arr=Array(24).fill(0);arr[0]=50;arr[nowH()]=arr[nowH()]+150;
  T.set(base({top:{},snapshot:{day:TODAY,revenue:100,readAt:new Date().toISOString()}}));
  const d=T.mnDayState&&base();const dd=base();dd.yesterdayHourly=arr;T.set(dd);
  const y=T.mnYesterdayHourly(TODAY);
  assert.ok(y,'overlay exists');assert.equal(y.cum[nowH()],200,'plain array is hour-indexed and cumulated');
});
ok('yesterday: retail key + combined adds on top; composition filter',()=>{
  const hh=nowH();
  const d=base();d.yesterdayHourlyRetail=[{h:hh,rev:100}];d.yesterdayHourly=[{h:hh,rev:40}];
  T.set(d);
  const both=T.mnYesterdayHourly(TODAY,{on:true,rt:true});
  assert.equal(both.cum[hh],140,'retail + combined summed');
  const onOnly=T.mnYesterdayHourly(TODAY,{on:true,rt:false});
  assert.equal(onOnly.cum[hh],40,'retail excluded when hero is online-only; combined still adds');
});
ok('yesterday: day-mismatched provenance is rejected',()=>{
  T.set(base({snapshot:{day:TODAY,revenue:100,readAt:new Date().toISOString(),yesterdayHourlyOnline:[{h:5,rev:200}],yesterdayHourlyOnlineProv:{day:FUT}}}));
  const y=T.mnYesterdayHourly(TODAY);
  assert.equal(y,null);
});

// 4. delta chips removed per user direction (2026-11-02): regression guard.
// Arsh circled "X% vs yesterday full day" on Online sales + Retail store overview and said remove.
function todayHtml(over){T.set(base(over));T.mode('today');return T.mnToday();}
ok('delta chips removed: Online sales card renders no vs-yesterday chip',()=>{
  let h=todayHtml({snapshot:{day:TODAY,revenue:2000,orderCount:2,readAt:new Date().toISOString()},history:[{d:YDAY,rev:1000}]});
  assert.ok(!h.includes('mn-delta'),'no mn-delta span');
  assert.ok(!h.includes('vs yesterday'),'no vs-yesterday text');
  assert.ok(h.includes('Online sales'),'card still renders');
});
ok('delta chips removed: Retail store overview Today KPI has no delta',()=>{
  T.set(base({retail:{day:TODAY,status:'ok',stores:[{name:'PTG',sales:5000,bills:3,units:3,billList:[]}]},retailHistory:[{d:YDAY,rev:3000}]}));
  const h=T.mnRetail();
  assert.ok(!h.includes('mn-delta'),'no mn-delta span in retail overview');
  assert.ok(h.includes('Today'),'Today KPI still renders');
  assert.ok(h.includes('Avg bill'),'other KPIs still render');
});
ok('undated day still hides Yesterday row and shows Undated',()=>{
  const h=todayHtml({snapshot:{day:null,revenue:2000,orderCount:2,readAt:new Date().toISOString()},retail:{day:null,status:'ok',stores:[{name:'PTG',sales:300,bills:1,units:1,billList:[]}]},history:[{d:YDAY,rev:1000}]});
  assert.ok(!h.includes('data-overview-day="yesterday"'),'Yesterday row hidden when undated');
  assert.ok(h.includes('Undated'),'Undated state shown');
});

ok('yesterday overlay: truncates at wall-clock hour on today, full day on past refDay',()=>{
  // Kept behavior (approved with the Today port): on today the yesterday overlay is cut at the
  // current wall-clock hour so it aligns with today's partial progress; the FULL yesterday total
  // still comes from the one yesterday figure (note/marker/row), never from this series.
  const full=Array(24).fill(100);
  T.set(base({snapshot:{day:TODAY,revenue:100,readAt:new Date().toISOString(),yesterdayHourlyOnline:full,yesterdayHourlyOnlineProv:{day:YDAY}}}));
  const y1=T.mnYesterdayHourly(TODAY);
  let last1=-1;y1.cum.forEach((v,h)=>{if(v!=null)last1=h;});
  assert.equal(last1,nowH(),'today ref: overlay ends at wall-clock hour '+nowH()+', got '+last1);
  const d2=addD(YDAY,-1);
  T.set(base({snapshot:{day:TODAY,revenue:100,readAt:new Date().toISOString(),yesterdayHourlyOnline:full,yesterdayHourlyOnlineProv:{day:d2}}}));
  const y2=T.mnYesterdayHourly(YDAY);
  let last2=-1;y2.cum.forEach((v,h)=>{if(v!=null)last2=h;});
  assert.equal(last2,23,'past refDay: full day drawn, got '+last2);
});

// 4b. prior-day panel: close provenance + post-midnight retail reads
const NOWISO=new Date().toISOString();
const YNOON=new Date(YDAY+'T12:00:00+05:30').toISOString();
function priorHtml(over){T.set(base(over));return T.priorDayContext();}
ok('prior-day: final close provenance -> "Final close", post-midnight retail accepted',()=>{
  const h=priorHtml({
    snapshot:{day:YDAY,revenue:260511,orderCount:85,readAt:NOWISO,at:'3 Nov, 12:01 AM',dayComplete:true,reportingDay:YDAY,closeLabel:'final close for 2 Nov'},
    retail:{day:YDAY,status:'ok',readAt:NOWISO,dayComplete:true,closeLabel:'final close for 2 Nov',stores:[{name:'PTG',sales:106630,bills:22,units:35,billList:[]}]}});
  assert.ok(h!=='','panel renders');
  assert.ok(h.includes('Retail'),'post-midnight retail snapshot shown');
  assert.ok((h.match(/Final close/g)||[]).length>=2,'both channels show Final close');
  assert.ok(!h.includes('not confirmed final'),'hardcoded not-final wording gone when all final');
  assert.ok(h.includes('Final close figures, confirmed by the source'),'header reflects final close');
});
ok('prior-day: post-midnight retail read accepted without close provenance, still not final',()=>{
  const h=priorHtml({
    snapshot:{day:YDAY,revenue:2000,orderCount:2,readAt:NOWISO},
    retail:{day:YDAY,status:'ok',readAt:NOWISO,stores:[{name:'PTG',sales:500,bills:1,units:1,billList:[]}]}});
  assert.ok(h.includes('Retail'),'retail accepted when read after midnight');
  assert.ok(h.includes('not confirmed final'),'not-final wording kept without provenance');
  assert.ok(!h.includes('Final close'),'no final wording without provenance');
});
ok('prior-day: dayComplete with mismatched reportingDay is not final',()=>{
  const h=priorHtml({
    snapshot:{day:YDAY,revenue:2000,orderCount:2,readAt:NOWISO,dayComplete:true,reportingDay:'1999-01-01'},
    retail:null});
  assert.ok(h.includes('not confirmed final'),'mismatched reportingDay not final');
  assert.ok(!h.includes('Final close'),'no final wording on day mismatch');
});
ok('prior-day: same-day retail read still accepted (regression), retail dayComplete binds to retail.day',()=>{
  const h=priorHtml({
    snapshot:{day:YDAY,revenue:2000,orderCount:2,readAt:NOWISO,dayComplete:true,reportingDay:YDAY},
    retail:{day:YDAY,status:'ok',readAt:YNOON,dayComplete:true,stores:[{name:'PTG',sales:500,bills:1,units:1,billList:[]}]}});
  assert.ok(h.includes('Retail'),'same-day read still accepted');
  assert.ok((h.match(/Final close/g)||[]).length>=2,'retail dayComplete alone marks retail final');
});
ok('prior-day: retail read for today is not shown as a prior day',()=>{
  const h=priorHtml({
    snapshot:{day:YDAY,revenue:2000,orderCount:2,readAt:NOWISO},
    retail:{day:TODAY,status:'ok',readAt:NOWISO,stores:[{name:'PTG',sales:500,bills:1,units:1,billList:[]}]}});
  assert.ok(h.includes('Online'),'online still shown');
  assert.ok(!h.includes('Retail'),'todays retail not a prior day');
});

// 5. mixed: hero online-only -> marker/note use online-only yesterday
ok('mixed: yesterday marker/note match hero composition',()=>{
  const h=todayHtml({history:[{d:YDAY,rev:4000}],retailHistory:[{d:YDAY,rev:1000}],
    snapshot:{day:TODAY,revenue:1500,orderCount:1,readAt:new Date().toISOString(),todayHourlyOnline:[{h:9,rev:1500}],todayHourlyOnlineProv:{day:TODAY,observedThroughHour:nowH()}},
    retail:{day:YDAY,status:'ok',stores:[{name:'PTG',sales:3000,bills:2,units:3,billList:[]}]}});
  assert.ok(h.includes('yesterday ₹4K total'),'note uses online-only yesterday, got: '+(h.match(/yesterday [^ ]+ total/)||['none'])[0]);
  assert.ok(!h.includes('yesterday ₹5K total'),'combined yesterday not used for the chart note');
  assert.ok(h.includes('Retail last read '+LBL(YDAY)),'stale retail legend says last read, no figure');
  assert.ok(!h.includes('Retail ₹3K'),'stale retail figure not shown as today');
});

// 5b. IST-midnight rollover: dated-but-stale reads never fill Today
ok('midnight: both sources stale -> dash hero, no fake zero, no stale figures, bills hidden',()=>{
  const st=[{name:'PTG',sales:106630,bills:22,units:35,billList:[{no:'R-9',amt:500,items:[{qty:1}]}]}];
  T.set(base({snapshot:{day:YDAY,revenue:260511,orderCount:85,readAt:YNOON,revenuePrev:111},retail:{day:YDAY,status:'ok',at:'2 Nov, 11:30 PM',stores:st},history:[{d:addD(YDAY,-1),rev:9}],retailHistory:[]}));
  const ds=T.mnDayState();assert.equal(ds.refDay,TODAY);assert.ok(ds.noToday);
  const h=T.mnToday();
  assert.ok(h.includes('No read yet for '+LBL(TODAY)),'hero says no read yet');
  assert.ok(h.includes('<div class="mn-big">—</div>'),'hero is a dash');
  assert.ok(h.includes('no orders read yet for '+LBL(TODAY))&&h.includes('no bills read yet for '+LBL(TODAY)),'cards');
  assert.ok(h.includes('Online last read '+LBL(YDAY))&&h.includes('Retail last read '+LBL(YDAY)),'legend');
  assert.ok(!h.includes('2.6')&&!h.includes('260,511')&&!h.includes('1.07')&&!h.includes('106,630')&&!h.includes('₹0'),'no stale or zero figures');
  assert.ok(!h.includes('Latest bills')&&!h.includes('R-9'),'latest bills hidden');
  assert.ok(h.includes('data-overview-day="yesterday"'),'yesterday stays reachable');
  assert.ok(!h.includes('>₹111'),'stale revenuePrev not used as yesterday');
});
ok('midnight: online fresh today, retail stale -> only retail dropped',()=>{
  T.set(base({snapshot:{day:TODAY,revenue:1500,orderCount:1,readAt:NOWISO},retail:{day:YDAY,status:'ok',stores:[{name:'PTG',sales:3000,bills:2,units:3,billList:[{no:'R-1',amt:3000,items:[{qty:1}]}]}]}}));
  const h=T.mnToday();
  assert.ok(h.includes('1.5K')||h.includes('1,500'),'online today shown');
  assert.ok(h.includes('no bills read yet for '+LBL(TODAY))&&!h.includes('Latest bills'),'retail dropped, bills hidden');
});

// 6. 7D window: legend + half cards use window-appropriate labels
ok('7D: legend day-suffixed, half cards dated, no "today" counts',()=>{
  T.set(base({history:[{d:YDAY,rev:4000}],retailHistory:[{d:YDAY,rev:1000}]}));
  T.mode('7');const h=T.mnToday();T.mode('today');
  assert.ok(h.includes('Online ₹5K · '+LBL(TODAY)),'online legend carries explicit day: '+(h.match(/Online ₹[^<]+/)||['none'])[0]);
  assert.ok(h.includes('Retail ₹3K · '+LBL(TODAY)),'retail legend carries explicit day');
  assert.ok(h.includes('2 orders on '+LBL(TODAY)),'half card dated: '+(h.match(/\d+ orders?[^(<]*/)||['none'])[0]);
  assert.ok(!h.includes('orders today'),'no today-flavored count in window mode');
  assert.ok(h.includes('Online + Retail,'),'window composition line present');
});

// 7. fresh render sanity: single Share/Settings rows, hollow dot, legend matches drawing
ok('fresh: one Share row, one Settings row, retail series drawn dashed',()=>{
  const oth=nowH();
  const h=todayHtml({snapshot:{day:TODAY,revenue:1500,orderCount:2,readAt:new Date().toISOString(),todayHourlyOnline:[{h:oth,rev:1500}],todayHourlyOnlineProv:{day:TODAY,observedThroughHour:oth}},
    retail:{day:TODAY,status:'ok',stores:[{name:'PTG',sales:300,bills:1,units:1,billList:[{no:'R-1',amt:300,_ms:Date.now(),items:[{qty:1}]}]}]}});
  assert.equal((h.match(/data-share="1"/g)||[]).length,1,'one Share row');
  assert.equal((h.match(/data-pm="1"/g)||[]).length,1,'one Settings row');
  const hr=T.mnTodayHourly();
  assert.ok(hr.cumRt&&hr.cumRt.some(p=>p&&p.v!=null),'retail series present (legend swatch matches a real series)');
  assert.ok(nowH()<2||h.includes('class="mn-rt"'),'retail path drawn when the series has 2+ points (single-point midnight hour draws no line - known, unchanged)');
  assert.ok(!h.includes('class="mn-cmp"'),'no dashed yesterday overlay in hourly chart');
});

ok('legend swatch matches drawing when retail has no times',()=>{
  const h=todayHtml({snapshot:{day:TODAY,revenue:1500,orderCount:2,readAt:new Date().toISOString(),todayHourlyOnline:[{h:9,rev:1500}],todayHourlyOnlineProv:{day:TODAY,observedThroughHour:nowH()}}});
  assert.ok(!h.includes('class="mn-rt"'),'no retail series without bill times');
  assert.ok(!h.includes('mn-swatch dash'),'legend uses non-series swatch when no retail curve');
  assert.ok(h.includes('mn-swatch dim'),'dim swatch shown for retail legend entry');
});

// 8. retail 7D/30D graphs end at the last completed day, never on today's partial value
ok('retail 7D/30D: window ends yesterday, today partial excluded',()=>{
  const RH=[];for(let i=7;i>=1;i--)RH.push({d:addD(TODAY,-i),rev:10000+i*100,by:{PTG:{rev:10000+i*100}}});
  T.set(base({retailHistory:RH,retail:{day:TODAY,status:'ok',at:'3 Nov, 1:00 AM',stores:[{name:'PTG',sales:50,bills:1,units:1,billList:[]}]}}));
  T.retRange('7');let h=T.mnRetail();T.retRange('30');const h30=T.mnRetail();T.retRange('today');
  assert.ok(h.includes('through '+LBL(YDAY)),'7D labelled through yesterday');
  assert.ok(h30.includes('through '+LBL(YDAY)),'30D labelled through yesterday');
  assert.ok(!h.includes('days supplied'),'all 7 completed days supplied, today not counted as a missing day');
});

console.log('\nALL PASS ('+n+')');process.exit(0);
