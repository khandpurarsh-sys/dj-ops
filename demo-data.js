/* DJ Ops demo mode: bundled sample dataset. Every value is fictional and exists
   only so the app's features can be explored without a paired device key.
   No real business figures, customers, keys or endpoints appear here. */
(function(){
function istNow(){return new Date(Date.now()+19800000)}
function iso(d){return d.toISOString().slice(0,10)}
function addD(s,n){const d=new Date(s+'T00:00:00+05:30');d.setDate(d.getDate()+n);return d.toISOString().slice(0,10)}
function nowIso(){return new Date().toISOString()}
function atLabel(){return new Date().toISOString()}
var STYLES=[
 ['DJ-CHESTER-NAVY','The Hurlingham Chester - Navy',8990],
 ['DJ-CHESTER-CAMEL','The Valcourt Chester - Camel',9490],
 ['DJ-SHIRT-WHITE','The Bellavere Shirt - White',3490],
 ['DJ-SHIRT-SKY','The Bellavere Shirt - Sky',3490],
 ['DJ-POLO-BLACK','The Havelock Polo - Black',2790],
 ['DJ-POLO-BURG','The Havelock Polo - Burgundy',2790],
 ['DJ-OVERSHIRT-OLIVE','The Tropez Overshirt - Olive',5950],
 ['DJ-TEE-CREAM','Signature Tee - Cream',2490],
 ['DJ-HALFSHIRT-SAND','Riviera Half Shirt - Sand',2990],
 ['DJ-NIGHT-NAVY','Lounge Set - Midnight',3990]];
var SIZES=['S','M','L','XL'];
function sku(i,s){return STYLES[i][0]+'-'+s}
function name(i){return STYLES[i][1]}
function price(i){return STYLES[i][2]}
function mkOrder(id,amt,ch,status,pay,time,items,extra){
 var o={id:id,amt:amt,ch:ch,status:status,pay:pay,time:time,items:items.map(function(x){return{sku:x[0],qty:x[1]}})};
 if(extra)for(var k in extra)o[k]=extra[k];return o}
function mkBill(no,time,amt,pay,items){return{no:no,customer:'Walk-in',time:time,amt:amt,units:items.reduce(function(n,x){return n+x[2]},0),pay:pay,items:items.map(function(x){return{sku:x[0],name:x[1],qty:x[2],amt:x[3]}})}}
function build(){
 var today=iso(istNow()),now=nowIso(),at=atLabel();
 var orders=[
  mkOrder('#DJ1048',8990,'Shopify','Packing','Prepaid','2:14 PM',[[sku(0,'M'),1]]),
  mkOrder('#DJ1047',12280,'Shopify','Label created','Prepaid','1:58 PM',[[sku(1,'L'),1],[sku(7,'L'),1]]),
  mkOrder('#DJ1046',3490,'Shopify','Pending verification','COD','1:31 PM',[[sku(2,'M'),1]]),
  mkOrder('#DJ1045',5950,'Shopify','Ready to ship','Prepaid','12:47 PM',[[sku(4,'XL'),1]],{awb:' SampleAWB0001',courier:'Sample Courier'}),
  mkOrder('#DJ1044',6280,'Myntra','Packing','Prepaid','12:20 PM',[[sku(4,'M'),1],[sku(8,'L'),1]]),
  mkOrder('#DJ1043',2790,'Myntra','Complete','Prepaid','11:52 AM',[[sku(5,'M'),1]]),
  mkOrder('#DJ1042',8480,'Shopify','Complete','Prepaid','11:20 AM',[[sku(3,'L'),1],[sku(7,'M'),2]]),
  mkOrder('#DJ1041',3990,'Nykaa','Packing','Prepaid','10:58 AM',[[sku(9,'L'),1]]),
  mkOrder('#DJ1040',5580,'Nykaa','Complete','Prepaid','10:15 AM',[[sku(6,'M'),2]]),
  mkOrder('#DJ1039',8990,'Shopify','Complete','COD','9:47 AM',[[sku(0,'L'),1]]),
  mkOrder('#DJ1038',3490,'Ajio','Complete','Prepaid','9:12 AM',[[sku(2,'S'),1]]),
  mkOrder('#DJ1037',5980,'Ajio','Cancelled','Prepaid','8:50 AM',[[sku(8,'M'),2]]),
  mkOrder('#DJ1036',11980,'Shopify','Complete','Prepaid','8:05 AM',[[sku(1,'M'),1],[sku(6,'L'),1]]),
  mkOrder('#DJ1035',2790,'Myntra','Complete','Prepaid','7:38 AM',[[sku(4,'S'),1]])];
 var pending=[
  mkOrder('#DJ0988',3490,'Shopify','Pending verification','COD','',[[sku(2,'M'),1]],{ageH:6}),
  mkOrder('#DJ0979',5950,'Shopify','Packing','Prepaid','',[[sku(4,'M'),1]],{ageH:19}),
  mkOrder('#DJ0971',2790,'Myntra','Label created','Prepaid','',[[sku(5,'L'),1]],{ageH:26}),
  mkOrder('#DJ0964',8480,'Shopify','Pending verification','COD','',[[sku(3,'M'),1],[sku(7,'M'),1]],{ageH:41}),
  mkOrder('#DJ0952',3990,'Nykaa','Packing','Prepaid','',[[sku(9,'M'),1]],{ageH:52}),
  mkOrder('#DJ0941',5980,'Ajio','Label created','Prepaid','',[[sku(8,'M'),2]],{ageH:68})];
 var histRev=[186420,142350,198770,121540,167280,173960,149820,205410,134670,172110];
 var history=histRev.map(function(rev,i){
  var d=addD(today,-(i+1));
  var sh=Math.round(rev*0.62),my=Math.round(rev*0.19),ny=Math.round(rev*0.12),aj=rev-sh-my-ny;
  var ords=32+((i*7)%15);
  return{d:d,rev:rev,items:ords+3,orders:ords,
   ch:{Shopify:sh,Myntra:my,Nykaa:ny,Ajio:aj},
   chItems:{Shopify:Math.round(ords*0.6),Myntra:Math.round(ords*0.2),Nykaa:Math.round(ords*0.12),Ajio:ords-Math.round(ords*0.6)-Math.round(ords*0.2)-Math.round(ords*0.12)},
   chOrders:{Shopify:Math.round(ords*0.62),Myntra:Math.round(ords*0.19),Nykaa:Math.round(ords*0.11),Ajio:ords-Math.round(ords*0.62)-Math.round(ords*0.19)-Math.round(ords*0.11)}};});
 var ptgBills=[
  mkBill('R-1201','11:42 AM',8450,'Card',[[sku(4,'M'),name(4),1,5950],[sku(7,'L'),name(7),1,2490]]),
  mkBill('R-1202','12:05 PM',3490,'UPI',[[sku(2,'M'),name(2),1,3490]]),
  mkBill('R-1203','12:31 PM',11980,'Card',[[sku(1,'L'),name(1),1,9490],[sku(7,'M'),name(7),1,2490]]),
  mkBill('R-1204','1:15 PM',2790,'UPI',[[sku(5,'M'),name(5),1,2790]]),
  mkBill('R-1205','1:48 PM',6480,'Card',[[sku(3,'M'),name(3),1,3490],[sku(8,'L'),name(8),1,2990]]),
  mkBill('R-1206','2:10 PM',3990,'Cash',[[sku(9,'L'),name(9),1,3990]]),
  mkBill('R-1207','2:36 PM',8980,'Card',[[sku(0,'M'),name(0),1,8990]]),
  mkBill('R-1208','3:05 PM',5580,'UPI',[[sku(6,'M'),name(6),2,5580]]),
  mkBill('R-1209','3:40 PM',2490,'Cash',[[sku(7,'S'),name(7),1,2490]])];
 var jaiBills=[
  mkBill('JPS-311','11:20 AM',6280,'Card',[[sku(4,'L'),name(4),1,5950]]),
  mkBill('JPS-312','12:02 PM',3490,'UPI',[[sku(2,'S'),name(2),1,3490]]),
  mkBill('JPS-313','12:44 PM',8990,'Card',[[sku(0,'L'),name(0),1,8990]]),
  mkBill('JPS-314','1:30 PM',4980,'UPI',[[sku(7,'M'),name(7),2,4980]]),
  mkBill('JPS-315','2:12 PM',2790,'Cash',[[sku(5,'S'),name(5),1,2790]]),
  mkBill('JPS-316','2:55 PM',3490,'UPI',[[sku(3,'L'),name(3),1,3490]]),
  mkBill('JPS-317','3:32 PM',3990,'Card',[[sku(9,'M'),name(9),1,3990]])];
 function totals(bl){return{sales:bl.reduce(function(n,b){return n+b.amt},0),bills:bl.length,units:bl.reduce(function(n,b){return n+b.units},0)}}
 var pt=totals(ptgBills),jt=totals(jaiBills);
 var retail={day:today,readAt:now,itemsReadAt:now,at:at,verifiedToday:true,
  stores:[
   {name:'PTG - Pacific Mall, Delhi',sales:pt.sales,bills:pt.bills,units:pt.units,returns:0,billList:ptgBills},
   {name:'DRJ Jaipur Pacific',sales:jt.sales,bills:jt.bills,units:jt.units,returns:0,billList:jaiBills}]};
 var rhRev=[[52140,38800],[44900,31250],[58600,42100],[39750,28900],[51280,36600],[47410,33950],[42890,30400],[55260,41080],[38920,27600],[50640,35200]];
 var retailHistory=rhRev.map(function(pair,i){
  var d=addD(today,-(i+1));
  function side(tot,nb){var items=[];var left=tot;for(var j=0;j<nb;j++){var si=(i+j)%10;var amt=j===nb-1?left:Math.min(left,price(si));left-=amt;items.push({sku:sku(si,SIZES[(i+j)%4]),name:name(si),qty:1,amt:amt})}
   return{rev:tot,bills:nb,units:nb,items:items}}
  var p=side(pair[0],6+((i*3)%4)),j=side(pair[1],4+((i*2)%3));
  return{d:d,rev:pair[0]+pair[1],bills:p.bills+j.bills,units:p.units+j.units,items:p.items.concat(j.items),
   by:{'PTG - Pacific Mall, Delhi':p,'DRJ Jaipur Pacific':j}};});
 function sellerRows(map){return map.map(function(x){return{sku:sku(x[0],x[1]),name:name(x[0]),qty:x[2],rev:x[2]*price(x[0])}})}
 var sellers={week:sellerRows([[0,'M',11],[4,'L',9],[2,'M',8],[1,'L',7],[7,'M',7],[5,'M',6],[9,'L',5],[8,'M',5],[3,'M',4],[6,'M',3]]),
  month:sellerRows([[0,'M',41],[4,'L',36],[2,'M',33],[1,'L',29],[7,'M',27],[5,'M',24],[9,'L',21],[8,'M',19],[3,'M',16],[6,'M',12]]),
  quarter:sellerRows([[0,'M',118],[4,'L',104],[2,'M',96],[1,'L',87],[7,'M',80],[5,'M',71],[9,'L',62],[8,'M',55],[3,'M',47],[6,'M',35]])};
 var retail7=sellers.week.map(function(r){return{sku:r.sku,name:r.name,qty:Math.max(1,Math.round(r.qty*0.6)),amt:Math.round(r.rev*0.6)}});
 var retail30=sellers.month.map(function(r){return{sku:r.sku,name:r.name,qty:Math.max(1,Math.round(r.qty*0.55)),amt:Math.round(r.rev*0.55)}});
 var stockRetail=[];STYLES.forEach(function(st,i){SIZES.forEach(function(s,j){stockRetail.push([st[1],s,(i*3+j*5)%14])})});
 var stockOnline=[];STYLES.forEach(function(st,i){SIZES.forEach(function(s,j){var oh=(i*7+j*3)%17;if((i+j)%9===0)oh=0;stockOnline.push([sku(i,s),st[1],oh,(i*11+j*4)%38])})});
 var stock={retail:{asOf:now,rows:stockRetail},online:{searchAsOf:now,asOf:now,totalSkus:stockOnline.length,rows:stockOnline}};
 var expenses={kind:'expenses',sid:'DEMO-EXP-001',source:'sample',
  payees:['Sample Textiles Co','Sample Porter Services','Sample Ads Network'],
  buckets:['production','porter_shipping','advertising'],
  months:[{m:today.slice(0,7),verifiedPaise:4120000,rows:3,items:[[0,2200000,0],[1,970000,1],[2,950000,2]]},
   {m:addD(today,-20).slice(0,7),verifiedPaise:5860000,rows:4,items:[[0,3400000,0],[0,860000,0],[1,720000,1],[2,880000,2]]}],
  undated:{paise:0,items:[]}};
 var main={businessData:false,note:'Demonstration data. All figures are sample values, not live business data.',
  snapshot:{ts:now,readAt:now,at:at,day:today,revenue:158340,revenuePrev:172110,items:47,orderCount:44,listings:214,
   ch:{Shopify:98200,Myntra:31100,Nykaa:18840,Ajio:10200},
   alerts:[{k:'Verification pending',v:3,tone:'pending_verification'},{k:'Packing due',v:5,tone:''}],
   pipeline:[{k:'Label created',v:6},{k:'Ready to ship',v:4}],sync:[]},
  orders:orders,pending:pending,history:history,retail:retail,retailHistory:retailHistory,
  sellers:sellers,sellersAsOf:now,retail7:retail7,retail7AsOf:now,retail30:retail30,retail30AsOf:now};
 return{main:main,stock:stock,expenses:expenses}}
window.DJ_DEMO={build:build};
})();
