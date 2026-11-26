import SwiftUI
import WebKit

/** 214-parity checkout (port of the shipped Android 214 state machine): one clean /cart
 *  load AFTER the view attaches (bridge + delegate in place - a mid-navigation JS
 *  evaluation is silently dropped, the bug behind his frozen "cart:sync" scrim), then a
 *  bounded verify-or-sync pass on every store-cart page finish. The opener JS is the
 *  same code the Android app injects against the same store/Fastrr, including the 25s
 *  empty-overlay rescue. iOS has no synthetic trusted taps, so the opener relies on
 *  buyCart() and an in-page button.click() - both are real JS on the page, no gesture
 *  gate in WKWebView. Scrim drops only for the overlay signal, a fastrr/shiprocket
 *  navigation, or a tap on the scrim. UPI/external schemes hand off to the system. */

private func isStoreCart(_ u: String) -> Bool {
    guard u.hasPrefix("https://dressjet.com/cart") else { return false }
    let rest = String(u.dropFirst("https://dressjet.com/cart".count))
    return rest.isEmpty || rest.hasPrefix("?") || rest.hasPrefix("#")
}

private func isFastrrPage(_ u: String) -> Bool {
    guard let url = URL(string: u), let h = url.host else { return false }
    let p = url.path
    return h.contains("shiprocket") || h.contains("pickrr") || (h == "dressjet.in" && p.hasPrefix("/checkout"))
}

private func isHostedCheckout(_ u: String) -> Bool {
    guard let url = URL(string: u), url.host == "dressjet.com" else { return false }
    return url.path.hasPrefix("/checkouts/")
}

/** The opener, verbatim semantics from Android 214: buyCart fast path, in-page button
 *  click fallback, one-shot late reload with loop guard, and the empty-overlay rescue
 *  (25s window, max 2, so a completed order never re-adds). */
private let OPEN_DEF = #"""
window.__djSame=function(c,exp){
  // EXACT cart match: same variants, same quantities, nothing extra. Count alone is NOT enough
  // (a stale cart with one other product has the same count and made checkout show that product).
  if(!c||!c.items)return false;
  var have={},want={},k,nh=0,nw=0;
  c.items.forEach(function(i){have[i.variant_id]=(have[i.variant_id]||0)+i.quantity;});
  exp.forEach(function(e){want[e.id]=(want[e.id]||0)+e.quantity;});
  for(k in have)nh++;for(k in want)nw++;
  if(nh!==nw)return false;
  for(k in want){if(have[k]!==want[k])return false;}
  return true;};
window.__djOpenFastrr=function(expCount,itemsJson){
if(window.__djFastrr)return;window.__djFastrr=true;
function rep(m){try{window.webkit.messageHandlers.djBridge.postMessage('report:'+m);}catch(e){}}
function ovl(){
  if(document.getElementById('fastrr-main-container'))return true;
  var h=document.getElementById('headless-iframe');
  if(h&&h.src&&h.src.indexOf('fastrr-boost-ui')>=0)return true;
  var f=document.querySelectorAll('iframe');
  for(var i=0;i<f.length;i++){var s=f[i].src||'';if(s.indexOf('https://fastrr-boost-ui.pickrr.com/?platform=')===0||s.indexOf('https://checkout.shiprocket.in')===0)return true;}
  return false;}
function findBtn(){
  var b=document.querySelector('button.sr-headless-checkout');
  if(b&&!b.disabled)return b;
  var bs=document.querySelectorAll('button');
  for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').toLowerCase();if(!bs[i].disabled&&(t.indexOf('shiprocket')>=0||t.indexOf('buy now')>=0))return bs[i];}
  return null;}
rep('inj:fired');
function go(){
var n=0,taps=0;
var t=setInterval(function(){n++;try{
  if(ovl()){rep('ovl:YES@'+n);try{sessionStorage.removeItem('djrl');}catch(e){}try{window.webkit.messageHandlers.djBridge.postMessage('fastrrOpen');}catch(e){}clearInterval(t);
    var t0=Date.now(),resc=0;
    var w=setInterval(function(){try{
      if(Date.now()-t0>25000){clearInterval(w);return;}
      fetch('/cart.js',{cache:'no-store'}).then(function(r){return r.json();}).then(function(c){
        if(c&&expCount>0&&!window.__djSame(c,itemsJson)&&resc<2){resc++;rep('cart:rescue '+resc);
          (async function(){try{
            await fetch('/cart/clear.js',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
            await fetch('/cart/add.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:itemsJson})});
            try{await fetch('/cart/update.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({attributes:{order_source:'DressJet app iOS'}})});}catch(e){}
            try{sessionStorage.removeItem('djrl');}catch(e){}
            location.reload();
          }catch(e){rep('cart:rescueErr '+e.message);}})();}
      }).catch(function(){});
    }catch(e){}},2000);
    return;}
  if(n===1){
    if(window.shiprocketCheckoutEvents&&typeof window.shiprocketCheckoutEvents.buyCart==='function'){
      try{window.shiprocketCheckoutEvents.buyCart({preventDefault:function(){},stopPropagation:function(){},target:findBtn()});rep('buyCart:called');}
      catch(e){rep('buyCart:err '+e.message);}
    }else rep('sr:absent@'+n);
  }
  if(n>=3&&taps<8&&(n-3)%8===0){
    var b=findBtn();
    if(b){b.scrollIntoView({block:'center'});taps++;rep('click:'+taps);try{b.click();}catch(e){rep('click:err '+e.message);}}
    else rep('btn:none@'+n);
  }
  if(n===5&&!findBtn()){
    var rc=0;try{rc=+(sessionStorage.getItem('djrl')||0);}catch(e){}
    if(rc<1){try{sessionStorage.setItem('djrl',''+(rc+1));}catch(e){}rep('cart:late-reload');location.reload();return;}
    rep('btn:none-stop');}
  if(n>300){rep('slow:still-trying');n=0;}
}catch(e){rep('tickErr '+e.message);}},400);}
// Gate: never open checkout on a cart that is not EXACTLY the bag. Wrong items: re-sync, reload once or twice, then open.
(async function(){try{
  var r=await fetch('/cart.js',{cache:'no-store'});var c=await r.json();
  if(expCount>0&&!window.__djSame(c,itemsJson)){
    rep('cart:wrong-items');
    await fetch('/cart/clear.js',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
    await fetch('/cart/add.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:itemsJson})});
    try{await fetch('/cart/update.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({attributes:{order_source:'DressJet app iOS'}})});}catch(e){}
    var fx=0;try{fx=+(sessionStorage.getItem('djfix')||0);}catch(e){}
    if(fx<2){try{sessionStorage.setItem('djfix',''+(fx+1));}catch(e){}window.__djFastrr=false;rep('cart:fixed-reload');location.reload();return;}
  }else{try{sessionStorage.removeItem('djfix');}catch(e){}}
}catch(e){rep('cart:gateErr '+e.message);}
go();})();
};
"""#;

private func openJs(_ expectedCount: Int, _ itemsJson: String) -> String {
    OPEN_DEF + "window.__djOpenFastrr(\(expectedCount),[\(itemsJson)]);"
}

private func syncBodyJs(_ itemsJson: String) -> String { """
try{
  await fetch('/cart/clear.js',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  var r=await fetch('/cart/add.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:[\(itemsJson)]})});
  try{await fetch('/cart/update.js',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({attributes:{order_source:'DressJet app iOS'}})});}catch(e){}
  rep('cart:synced '+r.status);
}catch(e){rep('cart:syncErr '+e.message);}
""" }

/** One verify-then-maybe-sync pass per store-cart page finish (bounded by the
 *  coordinator): count match alone is not enough - the item-rendered button must be on
 *  the DOM, or the overlay binds an empty cart. /cart.js reads bypass the HTTP cache. */
private func verifyOpenJs(_ expectedCount: Int, _ itemsJson: String) -> String {
    OPEN_DEF + """
(async function(){
function rep(m){try{window.webkit.messageHandlers.djBridge.postMessage('report:'+m);}catch(e){}}
try{
  var r=await fetch('/cart.js',{cache:'no-store'});var c=await r.json();
  if(window.__djSame(c,[\(itemsJson)])&&document.querySelector('button.sr-headless-checkout')){rep('cart:match');window.__djOpenFastrr(\(expectedCount),[\(itemsJson)]);return;}
  rep('cart:stale '+(c?c.item_count:'?')+' (wrong items, re-syncing)');
}catch(e){rep('cart:verifyErr '+e.message);}
if(window.__djCart)return;window.__djCart=true;
\(syncBodyJs(itemsJson))
var sy=0;try{sy=+(sessionStorage.getItem('djsync')||0);}catch(e){}
if(sy<2){try{sessionStorage.setItem('djsync',''+(sy+1));}catch(e){}rep('cart:synced-reload');location.reload();return;}
if(document.querySelector('button.sr-headless-checkout')){rep('cart:direct-open');window.__djOpenFastrr(\(expectedCount),[\(itemsJson)]);}
else location.reload();})();
"""
}

struct CheckoutView: View {
    @ObservedObject var bag: Bag
    let onBack: () -> Void
    @State private var navigating = true
    @State private var debug = "wv starting"
    @State private var t0 = Date()
    @State private var stamps = ""

    private var itemsJson: String {
        bag.lines.map { "{\"id\":\($0.variantId),\"quantity\":\($0.qty)}" }.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(dark: false, bagCount: bag.count, onBack: onBack)
            // Debug strip until Arsh says remove: one screenshot names the failing stage.
            // 220-ios: stage log with elapsed seconds so the next recording pins the slow stage.
            // 316: hidden for customers. The stage log still records; launch with -djdebug to show it.
            Color.clear.frame(height: 0)
                .onChange(of: debug) { _, d in
                    let t = Int(Date().timeIntervalSince(t0))
                    stamps = String((stamps + " | " + d + " +" + String(t) + "s").suffix(110))
                }
            if CommandLine.arguments.contains("-djdebug") {
                Text(stamps.isEmpty ? debug : stamps)
                    .font(Dj.assistant(10))
                    .tracking(0.4)
                    .foregroundStyle(Dj.cream)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 3)
                    .background(Dj.navyDeep)
            }
            ZStack {
                CheckoutWeb(expectedCount: bag.count, itemsJson: itemsJson,
                            navigating: $navigating, debug: $debug)
                if navigating {
                    VStack {
                        SerifTitle(text: "Taking you to secure checkout…", color: Dj.cream, size: 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Dj.navyDeep)
                    .contentShape(Rectangle())
                    .onTapGesture { navigating = false } // last-resort escape
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private struct CheckoutWeb: UIViewRepresentable {
    let expectedCount: Int
    let itemsJson: String
    @Binding var navigating: Bool
    @Binding var debug: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "djBridge")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        // ONE clean load after attach (see header note).
        web.load(URLRequest(url: URL(string: "https://dressjet.com/cart")!))
        // Watchdog kicks if the overlay never signals.
        for delay in [12.0, 24.0, 36.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak web] in
                guard let web, navigating else { return }
                debug = "kick:\(Int(delay))s"
                web.evaluateJavaScript(openJs(expectedCount, itemsJson))
            }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let parent: CheckoutWeb
        private var cartFinishes = 0
        private var orderPromptFired = false
        init(_ parent: CheckoutWeb) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            DispatchQueue.main.async {
                if body == "fastrrOpen" { self.parent.navigating = false }
                else if body.hasPrefix("report:") { self.parent.debug = String(body.dropFirst(7)) }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let u = webView.url?.absoluteString else { return }
            if isHostedCheckout(u) {
                // Server-302 safety net: never show Shopify's hosted checkout.
                webView.stopLoading()
                webView.load(URLRequest(url: URL(string: "https://dressjet.com/cart")!))
                return
            }
            if isFastrrPage(u) { DispatchQueue.main.async { self.parent.navigating = false } }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let u = webView.url?.absoluteString.lowercased(), !orderPromptFired,
               u.contains("thank") || u.contains("order-confirm") || u.contains("order_confirm") || u.contains("order-success") || u.contains("order_success") || u.contains("/orders/") {
                orderPromptFired = true
                Task { @MainActor in PushCoordinator.shared.onOrderPlaced() }
            }
            guard let u = webView.url?.absoluteString, isStoreCart(u) else { return }
            cartFinishes += 1
            if cartFinishes > 3 {
                DispatchQueue.main.async { self.parent.debug = "cart:guard" }
                webView.evaluateJavaScript(openJs(parent.expectedCount, parent.itemsJson))
                return
            }
            DispatchQueue.main.async { self.parent.debug = self.cartFinishes == 1 ? "cart:verify" : "cart:verify#\(self.cartFinishes)" }
            webView.evaluateJavaScript(verifyOpenJs(parent.expectedCount, parent.itemsJson))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            // Fastrr opens the Shopify account login via target=_blank; keep it in-app.
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: url))
                return
            }
            let u = url.absoluteString
            if isHostedCheckout(u) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: URL(string: "https://dressjet.com/cart")!))
                return
            }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                UIApplication.shared.open(url) // UPI and friends hand off to the system
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
