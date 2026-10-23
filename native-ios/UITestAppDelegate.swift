import UIKit
import Capacitor

// Standard Capacitor 7 AppDelegate plus a DEBUG-only, env-gated UI test driver
// used by the CI preview job to validate the unlock flow with a dummy passphrase.
// It activates only when the process is launched with DJOPS_UITEST=1 in its
// environment (SIMCTL_CHILD_DJOPS_UITEST=1 xcrun simctl launch ...) and never
// ships in Release builds.

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
        if ticks > 100 {
            timer?.invalidate()
            timer = nil
            return
        }
        guard let bridge = UIApplication.shared.delegate?.window??.rootViewController as? CAPBridgeViewController,
              let webView = bridge.webView else { return }
        webView.evaluateJavaScript(UITestDriver.script, completionHandler: nil)
    }

    // Fills any visible passphrase/password inputs with a dummy value and clicks
    // the primary action button (Create / Unlock / Continue / ...). Idempotent:
    // no-ops when no matching fields are on screen.
    static let script = """
    (function(){
      try {
        var pw = 'dummy-pass-1234';
        window.__djopsTest = window.__djopsTest || {clicks: 0, lastClick: 0};
        function visible(el){ var r = el.getBoundingClientRect(); return r.width > 40 && r.height > 10 && r.bottom > 0 && r.top < window.innerHeight; }
        function nativeSet(el, v){
          var proto = Object.getPrototypeOf(el);
          var desc = Object.getOwnPropertyDescriptor(proto, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
          if (desc && desc.set) { desc.set.call(el, v); } else { el.value = v; }
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
        }
        var inputs = Array.prototype.slice.call(document.querySelectorAll('input')).filter(function(i){
          var ph = (i.placeholder || '').toLowerCase();
          return visible(i) && (i.type === 'password' || ph.indexOf('passphrase') !== -1 || ph.indexOf('password') !== -1);
        });
        if (!inputs.length) { return 'no-fields'; }
        inputs.forEach(function(i){ if (i.value !== pw) { nativeSet(i, pw); } });
        var now = Date.now();
        if (now - window.__djopsTest.lastClick > 4000 && window.__djopsTest.clicks < 12) {
          var wanted = ['create','unlock','continue','submit','save','set passphrase','confirm'];
          var btns = Array.prototype.slice.call(document.querySelectorAll('button, a, [role="button"], input[type="submit"]')).filter(function(b){
            if (!visible(b)) { return false; }
            var t = ((b.innerText || b.value || '') + '').trim().toLowerCase();
            return wanted.indexOf(t) !== -1;
          });
          if (btns.length) {
            window.__djopsTest.lastClick = now;
            window.__djopsTest.clicks += 1;
            btns[0].click();
            return 'clicked';
          }
        }
        return 'filled';
      } catch (e) { return 'err'; }
    })();
    """
}
#endif
