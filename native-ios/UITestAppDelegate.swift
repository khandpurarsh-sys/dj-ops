import UIKit
import Capacitor

// Standard Capacitor 7 AppDelegate plus a DEBUG-only, env-gated UI test driver
// used by the CI preview job to validate the unlock flow with a dummy passphrase.
// Activates only when launched with DJOPS_UITEST=1 in the process environment
// (SIMCTL_CHILD_DJOPS_UITEST=1 xcrun simctl launch ...) and never ships in
// Release builds. Optional env flags: DJOPS_WRONGPASS=1 (one failed passphrase
// attempt before the correct one), DJOPS_SKIPDEV=1 (dismiss the phone-unlock
// offer with 'Not now' instead of attempting enrollment),
// DJOPS_ROUNDTRIP=1 + DJOPS_SEED_B64 (seed the committed dummy vault and
// decrypt the synthetic slim + full envelopes in-app),
// DJOPS_EXPMODE=match|mismatch|solo (after unlock, serve the synthetic ops +
// expense fixtures through a fetch stub, reload the feeds, and assert the v6
// Today + Expenses render in the DOM),
// DJOPS_LOCKTEST=1 (after the expense assertions, simulate leaving the app via
// a visibility override and assert the auto-lock gate and re-unlock).
// The green DJT overlay keeps a rolling 7-line action/error history so a single
// screenshot proves what happened regardless of screenshot latency.
// Also carries the same privacy cover as the production AppDelegate.

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    private let privacyCoverTag = 991122

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DJOPS_UITEST"] == "1" {
            UITestDriver.shared.start()
        }
        #endif
        return true
    }

    private func addPrivacyCover() {
        guard let w = window, w.viewWithTag(privacyCoverTag) == nil else { return }
        let v = UIView(frame: w.bounds)
        v.tag = privacyCoverTag
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.backgroundColor = UIColor(red: 10.0/255.0, green: 22.0/255.0, blue: 40.0/255.0, alpha: 1)
        let l = UILabel()
        l.text = "DJ Ops"
        l.textColor = UIColor(white: 1, alpha: 0.55)
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        w.addSubview(v)
    }

    private func removePrivacyCover() {
        window?.viewWithTag(privacyCoverTag)?.removeFromSuperview()
    }

    func applicationWillResignActive(_ application: UIApplication) { addPrivacyCover() }
    func applicationDidEnterBackground(_ application: UIApplication) { addPrivacyCover() }
    func applicationDidBecomeActive(_ application: UIApplication) { removePrivacyCover() }
    func applicationWillEnterForeground(_ application: UIApplication) {}
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
        if ticks > 200 {
            timer?.invalidate()
            timer = nil
            return
        }
        guard let bridge = UIApplication.shared.delegate?.window??.rootViewController as? CAPBridgeViewController,
              let webView = bridge.webView else { return }
        webView.evaluateJavaScript(UITestDriver.script) { result, _ in
            if let s = result as? String, s.hasPrefix("DJVERDICT ") {
                UIPasteboard.general.string = s
            }
        }
    }

    private static let wrongPass = ProcessInfo.processInfo.environment["DJOPS_WRONGPASS"] == "1" ? "true" : "false"
    private static let skipDev = ProcessInfo.processInfo.environment["DJOPS_SKIPDEV"] == "1" ? "true" : "false"
    private static let roundtrip = ProcessInfo.processInfo.environment["DJOPS_ROUNDTRIP"] == "1" ? "true" : "false"
    private static let expMode = ProcessInfo.processInfo.environment["DJOPS_EXPMODE"] ?? ""
    private static let lockTest = ProcessInfo.processInfo.environment["DJOPS_LOCKTEST"] == "1" ? "true" : "false"
    private static let seedB64 = ProcessInfo.processInfo.environment["DJOPS_SEED_B64"] ?? ""

    static let script: String = """
    (function(){
      try {
        var NL = String.fromCharCode(10);
        var pw = 'dummy-pass-1234';
        var st = window.__djopsTest = window.__djopsTest || {clicks: 0, lastClick: 0, wrongDone: false, pauseUntil: 0, hist: [], lastErr: '', t0: Date.now()};
        var WRONGPASS = __WRONGPASS__;
        var SKIPDEV = __SKIPDEV__;
        var ROUNDTRIP = __ROUNDTRIP__;
        var EXPMODE = '__EXPMODE__';
        var LOCKTEST = __LOCKTEST__;
        var SEEDB = '__SEED_B64__';
        function push(line){
          if (!line) { return; }
          if (st.hist.length && st.hist[st.hist.length - 1].slice(9) === line) { return; }
          st.hist.push(new Date().toISOString().slice(11, 19) + ' ' + line);
          if (st.hist.length > 7) { st.hist.shift(); }
        }
        function mark2(t, top){
          if (!document.body) { return; }
          var d = document.createElement('div');
          d.style.cssText = 'position:fixed;top:' + top + 'px;left:8px;right:8px;z-index:99999;background:#ff0;color:#000;font:15px monospace;padding:8px;word-break:break-all';
          d.textContent = t;
          document.body.appendChild(d);
          push(t);
          st.marks = (st.marks || []).concat(t);
        }
        function render(msg){
          var err = document.querySelector('.err');
          var errT = err && err.textContent ? String(err.textContent).trim() : '';
          if (errT && errT !== st.lastErr) {
            st.lastErr = errT;
            push('APPERR:' + errT.slice(0, 80));
            st.banners = st.banners || 0;
            if (st.banners < 6 && document.body) {
              var b = document.createElement('div');
              b.style.cssText = 'position:fixed;top:' + (210 + st.banners * 54) + 'px;left:8px;right:8px;z-index:99999;background:#ff0;color:#000;font:13px monospace;padding:6px;word-break:break-all';
              b.textContent = 'SEEN-ERR: ' + errT;
              document.body.appendChild(b);
              st.banners += 1;
            }
          }
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
          if (now < st.pauseUntil || now - st.lastClick < 4000 || st.clicks >= 40) { return null; }
          var els = Array.prototype.slice.call(document.querySelectorAll('button, a, [role="button"], input[type="submit"]')).filter(visible);
          for (var i = 0; i < els.length; i++) {
            var t = ((els[i].innerText || els[i].value || '') + '').trim().toLowerCase();
            if (list.indexOf(t) !== -1) { st.lastClick = now; st.clicks += 1; els[i].click(); return t; }
          }
          return null;
        }
        function installFixtureStub(seed){
          if (window.__djStub) { return; }
          var ids = {'1': 900001, '3': 900003, '87': 900087, '88': 900088};
          var bodies = {'1': JSON.stringify(seed.payloadSlim), '3': JSON.stringify(seed.payloadFull), '87': JSON.stringify(seed.expA)};
          if (seed.expB) { bodies['88'] = JSON.stringify(seed.expB); }
          var batch = Object.keys(bodies).map(function(n){
            return {issue_url: 'https://api.github.com/repos/khandpurarsh-sys/dj-ops/issues/' + n,
                    body: bodies[n], created_at: '2026-10-24T03:40:00Z',
                    user: {login: 'khandpurarsh-sys'}, id: ids[n]};
          });
          var of = window.fetch;
          window.fetch = function(url, opts){
            url = String(url);
            function res(code, obj){ return Promise.resolve({ok: code >= 200 && code < 300, status: code, headers: {get: function(){ return null; }}, json: function(){ return Promise.resolve(obj); }}); }
            if (url.indexOf('api.github.com') >= 0) {
              if (url.indexOf('/issues/comments') >= 0) { return res(200, batch); }
              var m = url.match(/\\/issues\\/(\\d+)(\\/comments)?/);
              if (m && m[2] && bodies[m[1]]) { return res(200, [{body: bodies[m[1]], user: {login: 'khandpurarsh-sys'}, id: ids[m[1]]}]); }
              if (m && m[2]) { return res(200, []); }
              if (m) { return res(200, {comments: 0}); }
            }
            return of(url, opts);
          };
          ['dj_feed_batch_v2', 'dj_last', 'dj_slim', 'dj_exp', 'dj_expc', 'dj_stk', 'dj_feed_pause_until', 'dj_api_fallback_after', 'dj_static_feed'].forEach(function(k){ try { localStorage.removeItem(k); } catch (e) {} });
          window.__djStub = 1;
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
          if (EXPMODE && !window.__djStub) {
            installFixtureStub(JSON.parse(atob(SEEDB)));
            push('stub-installed');
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
            if (EXPMODE) { st.stage = 'wait'; st.lastRf = Date.now(); }
            return render('rt-running');
          }
        }
        if (ROUNDTRIP && EXPMODE && st.stage === 'done' && !st.verdictDone) {
          st.verdictDone = 1;
          st.verdict = 'DJVERDICT ' + EXPMODE + ' ' + (st.marks || []).join(' | ');
        }
        if (ROUNDTRIP && EXPMODE && st.stage && st.stage !== 'done') {
          if (st.stage === 'wait') {
            var tabs = [].map.call(document.querySelectorAll('.tabbar button'), function(b){ return b.getAttribute('data-t') || ''; });
            if (!tabs.length) {
              var rf1 = document.getElementById('rf');
              if (rf1 && Date.now() - (st.lastRf || 0) > 8000) { st.lastRf = Date.now(); rf1.click(); return render('exp-refresh-retry'); }
              if (Date.now() - st.t0 > 120000) { mark2('EXP-RENDER-TIMEOUT no tabbar', 194); st.stage = 'done'; }
              return render('exp-wait');
            }
            var expBtn0 = document.querySelector('.tabbar button[data-t="exp"]');
            if (!expBtn0) { mark2('EXP-TAB-FAIL tabs=' + tabs.join(','), 194); st.stage = 'done'; return render('exp-tab-fail'); }
            mark2('EXP-TABS-OK ' + tabs.join(','), 194);
            expBtn0.click();
            st.stage = 'expview';
            return render('exp-tab-clicked');
          }
          if (st.stage === 'expview') {
            var rt2 = ((document.getElementById('root') || {}).textContent || '').toLowerCase();
            if (EXPMODE === 'match') {
              var merged = rt2.indexOf('12,500') >= 0 && rt2.indexOf('new vendor fx') >= 0 && rt2.indexOf('not added to the payment total') >= 0 && rt2.indexOf('undated') >= 0;
              mark2(merged ? 'EXP-MERGED-OK oct=12,500 remap=NewVendor sections+undated' : 'EXP-MERGED-FAIL len=' + rt2.length, 256);
            } else {
              var aonly = rt2.indexOf('12,500') >= 0 && rt2.indexOf('new vendor fx') < 0 && rt2.indexOf('not added to the payment total') < 0 && rt2.indexOf('undated') < 0;
              mark2(aonly ? 'EXP-AONLY-OK ' + EXPMODE + ' verified-only' : 'EXP-AONLY-FAIL ' + EXPMODE + ' len=' + rt2.length, 256);
            }
            st.stage = LOCKTEST ? 'lock' : 'done';
            return render('exp-asserted');
          }
          if (st.stage === 'lock') {
            window.__djHid = false;
            try {
              Object.defineProperty(document, 'hidden', {configurable: true, get: function(){ return window.__djHid; }});
            } catch (e) { mark2('LOCK-SKIP hidden not overridable', 318); st.stage = 'done'; return render('lock-skip'); }
            window.__djHid = true;
            document.dispatchEvent(new Event('visibilitychange'));
            st.stage = 'lockwait';
            st.lockAt = Date.now();
            return render('lock-forced-hidden');
          }
          if (st.stage === 'lockwait') {
            var gate = document.querySelector('.lock input#pw');
            if (gate && !document.querySelector('.tabbar')) {
              mark2('LOCK-AUTO-OK gate after background', 318);
              window.__djHid = false;
              document.dispatchEvent(new Event('visibilitychange'));
              st.stage = 'reunlock';
              return render('lock-ok-returning');
            }
            if (Date.now() - st.lockAt > 15000) { mark2('LOCK-AUTO-FAIL no gate', 318); st.stage = 'done'; }
            return render('lock-wait');
          }
          if (st.stage === 'reunlock') {
            if (document.querySelector('.tabbar')) {
              mark2('LOCK-REUNLOCK-OK content restored', 380);
              st.stage = 'done';
              return render('lock-reunlock-ok');
            }
            if (Date.now() - st.lockAt > 60000) { mark2('LOCK-REUNLOCK-FAIL', 380); st.stage = 'done'; }
            // fall through: the normal input branch below fills the passphrase
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
        var c3 = clickText(SKIPDEV ? ['continue', 'not now'] : ['continue', 'turn on phone unlock']);
        if (c3 === 'turn on phone unlock') { st.pauseUntil = Date.now() + 30000; }
        render(c3 ? 'clicked:' + c3 : 'idle');
        return st.verdict || '';
      } catch (e) { return 'err'; }
    })();
    """.replacingOccurrences(of: "__WRONGPASS__", with: wrongPass)
       .replacingOccurrences(of: "__SKIPDEV__", with: skipDev)
       .replacingOccurrences(of: "__ROUNDTRIP__", with: roundtrip)
       .replacingOccurrences(of: "__EXPMODE__", with: expMode)
       .replacingOccurrences(of: "__LOCKTEST__", with: lockTest)
       .replacingOccurrences(of: "__SEED_B64__", with: seedB64)
}
#endif
