import UIKit
import Capacitor

// Production AppDelegate: standard Capacitor 7 wiring plus a privacy cover
// that hides app content from the app switcher snapshot and while the app is
// inactive. The web layer separately wipes unlocked state when the app is
// backgrounded (native shell only), so returning shows the unlock gate.

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    private let privacyCoverTag = 991122

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window?.backgroundColor = Self.navy
        NotificationCenter.default.addObserver(self, selector: #selector(syncFullScreen), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncFullScreen), name: UIScene.didActivateNotification, object: nil)
        DispatchQueue.main.async { self.syncFullScreen() }
        return true
    }

    // Foldable / large-screen full-screen guard: never let the window sit
    // letterboxed inside the screen, and never let the web view inset its
    // content. Any gap that remains shows the app navy, not system black.
    private static let navy = UIColor(red: 10.0/255.0, green: 22.0/255.0, blue: 40.0/255.0, alpha: 1)

    @objc func syncFullScreen() {
        guard let w = window else { return }
        w.backgroundColor = Self.navy
        let screenBounds = w.screen.bounds
        if w.frame != screenBounds { w.frame = screenBounds }
        if let root = w.rootViewController {
            root.view.backgroundColor = Self.navy
            if root.view.frame != w.bounds { root.view.frame = w.bounds }
            if let bridge = root as? CAPBridgeViewController, let wv = bridge.webView {
                wv.scrollView.contentInsetAdjustmentBehavior = .never
                wv.backgroundColor = Self.navy
                wv.scrollView.backgroundColor = Self.navy
                if wv.frame != root.view.bounds { wv.frame = root.view.bounds }
            }
        }
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
    func applicationDidBecomeActive(_ application: UIApplication) { removePrivacyCover(); syncFullScreen() }
    func applicationWillEnterForeground(_ application: UIApplication) {}

    func applicationWillTerminate(_ application: UIApplication) {}

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
