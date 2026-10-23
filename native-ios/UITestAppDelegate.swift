import UIKit
import Capacitor

// Standard Capacitor 7 AppDelegate plus a DEBUG-only, env-gated UI test driver
// used by the CI preview job to validate the unlock flow with a dummy passphrase.
// Activates only when launched with DJOPS_UITEST=1 in the process environment
// (SIMCTL_CHILD_DJOPS_UITEST=1 xcrun simctl launch ...) and never ships in
// Release builds. Optional env flags: DJOPS_WRONGPASS=1 (one failed passphrase
// attempt before the correct one) and DJOPS_FALLBACK=1 (click the
// "Use passphrase" link when present, to exercise the phone-unlock fallback).

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
        if ticks > 120 {
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

    // Fills visible passphrase/password inputs with a dummy value and clicks the
    // primary action buttons. Idempotent and rate-limited; no-ops on screens
    // with nothing to do.
    static let script: String = """
    (function(){
      try {
        var pw = 'dummy-pass-1234';
        var st = window.__djopsTest = window.__djopsTest || {clicks: 0, lastClick: 0, wrongDone: false, pauseUntil: 0};
        var WRONGPASS = __WRONGPASS__;
        var FALLBACK = __FALLBACK__;
        var ROUNDTRIP = __ROUNDTRIP__;
        var SEEDB = '__SEED_B64__';
        if (st.pauseUntil && Date.now() < st.pauseUntil) { return 'paused'; }
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
          if (now - st.lastClick < 4000 || st.clicks >= 24) { return null; }
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
            return 'seeded';
          }
          if (!inputs.length && !window.__rtDone && st.clicks > 0) {
            window.__rtDone = 1;
            (async function(){
              function mark(t){ var d = document.createElement('div'); d.style.cssText = 'position:fixed;top:70px;left:8px;right:8px;z-index:99999;background:#ff0;color:#000;font:16px monospace;padding:10px;word-break:break-all'; d.textContent = t; document.body.appendChild(d); }
              try {
                var seed = JSON.parse(atob(SEEDB));
                var m = await import('./crypto.js?v=3');
                var v = JSON.parse(localStorage.getItem('dj_vault'));
                var priv = await m.unlock(v, 'dummy-pass-1234');
                var k = await m.kid(v.pub);
                var data = await m.decryptPayload(seed.payload, priv, k);
                mark('ROUNDTRIP-OK ' + (data && data.synthetic));
              } catch (e) { mark('ROUNDTRIP-FAIL ' + (e && e.message)); }
            })();
            return 'rt-running';
          }
        }
        if (inputs.length) {
          if (WRONGPASS && !st.wrongDone && inputs.length === 1 && (inputs[0].placeholder || '') === 'Passphrase') {
            nativeSet(inputs[0], 'wrong-pass-999');
            st.wrongDone = true;
            var c0 = clickText(['unlock']);
            st.pauseUntil = Date.now() + 25000;
            return 'wrong-attempted:' + c0;
          }
          inputs.forEach(function(i){ if (i.value !== pw) { nativeSet(i, pw); } });
          var c1 = clickText(['create', 'unlock']);
          return c1 ? 'clicked:' + c1 : 'filled';
        }
        if (FALLBACK) { var c2 = clickText(['use passphrase']); if (c2) { return 'clicked:' + c2; } }
        var c3 = clickText(['continue', 'turn on phone unlock']);
        return c3 ? 'clicked:' + c3 : 'idle';
      } catch (e) { return 'err'; }
    })();
    """.replacingOccurrences(of: "__WRONGPASS__", with: wrongPass)
       .replacingOccurrences(of: "__FALLBACK__", with: fallback)
       .replacingOccurrences(of: "__ROUNDTRIP__", with: roundtrip)
       .replacingOccurrences(of: "__SEED_B64__", with: seedB64)
}
#endif
