import UIKit
import Capacitor

// Production AppDelegate: standard Capacitor 7 wiring plus a privacy cover
// that hides app content from the app switcher snapshot and while the app is
// inactive. The web layer separately wipes unlocked state when the app is
// backgrounded (native shell only), so returning shows the unlock gate.

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Scene lifecycle (iOS 27 SDK requires it): the window belongs to the
    // scene, so expose it here for the privacy cover and the test driver.
    var window: UIWindow? {
        get { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first }
        set { }
    }

    private let privacyCoverTag = 991122

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func addPrivacyCover() {
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

    func removePrivacyCover() {
        window?.viewWithTag(privacyCoverTag)?.removeFromSuperview()
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var app: AppDelegate? { UIApplication.shared.delegate as? AppDelegate }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // The window and Capacitor bridge view controller come from the
        // storyboard named by UISceneStoryboardFile in Info.plist.
        for c in connectionOptions.urlContexts {
            _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: c.url, options: [:])
        }
    }

    func sceneWillResignActive(_ scene: UIScene) { app?.addPrivacyCover() }
    func sceneDidEnterBackground(_ scene: UIScene) { app?.addPrivacyCover() }
    func sceneDidBecomeActive(_ scene: UIScene) { app?.removePrivacyCover() }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for c in URLContexts {
            _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: c.url, options: [:])
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }
}
