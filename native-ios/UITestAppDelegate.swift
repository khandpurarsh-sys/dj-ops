import UIKit
import Capacitor

// Standard Capacitor 7 AppDelegate plus a DEBUG-only, env-gated UI test driver
// used by the CI preview job to validate the unlock flow with a dummy passphrase.
// Activates only when launched with DJOPS_UITEST=1 in the process environment
// (SIMCTL_CHILD_DJOPS_UITEST=1 xcrun simctl launch ...) and never ships in
// Release builds. Optional env flags: DJOPS_WRONGPASS=1 (one failed passphrase
// attempt before the correct one), DJOPS_FALLBACK=1 (click the "Use passphrase"
// link after a delay, to exercise the phone-unlock fallback),
// DJOPS_ROUNDTRIP=1 + DJOPS_SEED_B64 (seed the committed dummy vault and
// decrypt the peer publisher's synthetic slim + full envelopes in-app).
// The green DJT overlay keeps a rolling 7-line action/error history so a single
// screenshot proves what happened regardless of screenshot latency.

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DJOPS_UITEST"] == "1" {
            UITestDriver.shared.start()
        }
        #endif
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

#if DEBUG
final class UITestDriver {
    static let shared = UITestDriver()
    private var timer: Timer?
    private var ticks = 0

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
    }

    private func tick() {
        ticks += 1
        if ticks > 160 {
            timer?.invalidate()
            timer = nil
            return
        }
        guard let bridge = UIApplication.shared.delegate?.window??.rootViewController as? CAPBridgeViewController,
              let webView = bridge.webView else { return }
        webView.evaluateJavaScript(UITestDriver.script, completionHandler: nil)
    }

    private static let wrongPass = ProcessInfo.processInfo.environment["DJOPS_WRONGPASS"] == "1" ? "true" : "false"
    private static let fallback = ProcessInfo.processInfo.environment["DJOPS_FALLBACK"] == "1" ? "true" : "false"
    private static let roundtrip = ProcessInfo.processInfo.environment["DJOPS_ROUNDTRIP"] == "1" ? "true" : "false"
    private static let seedB64 = ProcessInfo.processInfo.environment["DJOPS_SEED_B64"] ?? ""

    static let script: String = """
    (function(){
      try {
        var NL = String.fromCharCode(10);
        var pw = 'dummy-pass-1234';
        var st = window.__djopsTest = window.__djopsTest || {clicks: 0, lastClick: 0, wrongDone: false, pauseUntil: 0, hist: [], lastErr: '', t0: Date.now()};
        var WRONGPASS = __WRONGPASS__;
        var FALLBACK = __FALLBACK__;
        var ROUNDTRIP = __ROUNDTRIP__;
        var SEEDB = '__SEED_B64__';
        function push(line){
          if (!line) { return; }
          if (st.hist.length && st.hist[st.hist.length - 1].slice(9) === line) { return; }
          st.hist.push(new Date().toISOString().slice(11, 19) + ' ' + line);
          if (st.hist.length > 7) { st.hist.shift(); }
        }
        function render(msg){
          var err = document.querySelector('.err');
          var errT = err && err.textContent ? String(err.textContent).trim() : '';
          if (errT && errT !== st.lastErr) { st.lastErr = errT; push('APPERR:' + errT.slice(0, 80)); }
          push(msg);
          var d = document.getElementById('__djt');
          if (!d) {
            d = document.createElement('pre');
            d.id = '__djt';
            d.style.cssText = 'position:fixed;left:0;right:0;bottom:0;margin:0;z-index:99999;background:#000;color:#0f0;font:9px monospace;padding:3px 5px;white-space:pre-wrap;word-break:break-all';
            if (document.body) { document.body.appendChild(d); }
          }
          var dev = ''; try { dev = localStorage.getItem('dj_dev') ? 'dev:1' : 'dev:0'; } catch (e) {}
          var v = ''; try { v = localStorage.getItem('dj_vault') ? 'vault:1' : 'vault:0'; } catch (e) {}
          d.textContent = 'DJT ' + v + ' ' + dev + NL + st.hist.join(NL);
        }
        function visible(el){ var r = el.getBoundingClientRect(); return r.width > 40 && r.height > 10 && r.bottom > 0 && r.top < window.innerHeight; }
        function nativeSet(el, v){
          var proto = Object.getPrototypeOf(el);
          var desc = Object.getOwnPropertyDescriptor(proto, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
          if (desc && desc.set) { desc.set.call(el, v); } else { el.value = v; }
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
        }
        function clickText(list){
          var now = Date.now();
          if (now < st.pauseUntil || now - st.lastClick < 4000 || st.clicks >= 30) { return null; }
          var els = Array.prototype.slice.call(document.querySelectorAll('button, a, [role="button"], input[type="submit"]')).filter(visible);
          for (var i = 0; i < els.length; i++) {
            var t = ((els[i].innerText || els[i].value || '') + '').trim().toLowerCase();
            if (list.indexOf(t) !== -1) { st.lastClick = now; st.clicks += 1; els[i].click(); return t; }
          }
          return null;
        }
        var inputs = Array.prototype.slice.call(document.querySelectorAll('input')).filter(function(i){
          var ph = (i.placeholder || '').toLowerCase();
          return visible(i) && (i.type === 'password' || ph.indexOf('passphrase') !== -1 || ph.indexOf('password') !== -1);
        });
        if (ROUNDTRIP) {
          if (!localStorage.getItem('dj_vault')) {
            var seed0 = JSON.parse(atob(SEEDB));
            localStorage.setItem('dj_vault', JSON.stringify(seed0.vault));
            localStorage.setItem('dj_devno', '1');
            location.reload();
            return render('seeded');
          }
          if (!inputs.length && !window.__rtDone && st.clicks > 0) {
            window.__rtDone = 1;
            (async function(){
              function mark(t, top){
                var d = document.createElement('div');
                d.style.cssText = 'position:fixed;top:' + top + 'px;left:8px;right:8px;z-index:99999;background:#ff0;color:#000;font:15px monospace;padding:8px;word-break:break-all';
                d.textContent = t;
                document.body.appendChild(d);
              }
              try {
                var seed = JSON.parse(atob(SEEDB));
                var m = await import('./crypto.js?v=3');
                var v = JSON.parse(localStorage.getItem('dj_vault'));
                var priv = await m.unlock(v, 'dummy-pass-1234');
                var k = await m.kid(v.pub);
                try {
                  var d1 = await m.decryptPayload(seed.payloadSlim, priv, k);
                  mark('RT-SLIM-OK ' + JSON.stringify(d1).slice(0, 45), 70);
                } catch (e1) { mark('RT-SLIM-FAIL ' + (e1 && e1.message), 70); }
                try {
                  var d2 = await m.decryptPayload(seed.payloadFull, priv, k);
                  mark('RT-FULL-OK ' + JSON.stringify(d2).slice(0, 45), 132);
                } catch (e2) { mark('RT-FULL-FAIL ' + (e2 && e2.message), 132); }
              } catch (e) { mark('RT-SETUP-FAIL ' + (e && e.message), 70); }
            })();
            return render('rt-running');
          }
        }
        if (inputs.length) {
          if (WRONGPASS && !st.wrongDone && inputs.length === 1 && (inputs[0].placeholder || '') === 'Passphrase') {
            nativeSet(inputs[0], 'wrong-pass-999');
            st.wrongDone = true;
            st.lastClick = 0;
            var c0 = clickText(['unlock']);
            st.pauseUntil = Date.now() + 20000;
            return render('wrong-attempted:' + c0);
          }
          inputs.forEach(function(i){ if (i.value !== pw) { nativeSet(i, pw); } });
          var c1 = clickText(['create', 'unlock']);
          return render(c1 ? 'clicked:' + c1 : 'filled');
        }
        if (FALLBACK && Date.now() - st.t0 > 12000) {
          var c2 = clickText(['use passphrase']);
          if (c2) { return render('clicked:' + c2); }
        }
        var c3 = clickText(['continue', 'turn on phone unlock']);
        if (c3 === 'turn on phone unlock') { st.pauseUntil = Date.now() + 30000; }
        return render(c3 ? 'clicked:' + c3 : 'idle');
      } catch (e) { return 'err'; }
    })();
    """.replacingOccurrences(of: "__WRONGPASS__", with: wrongPass)
       .replacingOccurrences(of: "__FALLBACK__", with: fallback)
       .replacingOccurrences(of: "__ROUNDTRIP__", with: roundtrip)
       .replacingOccurrences(of: "__SEED_B64__", with: seedB64)
}
#endif
