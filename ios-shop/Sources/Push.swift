import Foundation
import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// Storage model: users/{uid}/devices/{installId}. No tokens in users/{uid}.

struct PushWritten: Equatable { var uid: String; var token: String; var env: String; var appVersion: String }
struct PendingDelete: Equatable { var uid: String; var installId: String }

protocol PushStoring: AnyObject {
    var installId: String { get }                 // random UUID, created once, persisted
    var written: PushWritten? { get set }
    var pendingDelete: PendingDelete? { get set }
    var lastPromptAt: Date? { get set }
    var pendingToken: String? { get set }
}
protocol PushWriting {
    func upsert(uid: String, installId: String, fields: [String: String]) async -> Bool   // masked PATCH, mask = keys
    func delete(uid: String, installId: String) async -> Bool                              // 404 = success
}
enum PushOutcome: Equatable { case skipped(String), written, deleted, failed }

enum DevicePayload {
    static func fields(token: String, env: String, appVersion: String, now: Date) -> [String: String] {
        ["token": token, "platform": "ios", "env": env, "appVersion": appVersion, "updatedAt": String(Int(now.timeIntervalSince1970 * 1000))]
    }
    static func body(_ f: [String: String]) -> [String: Any] { ["fields": f.mapValues { ["stringValue": $0] }] }
    static func mask(_ keys: [String]) -> String { keys.sorted().map { "updateMask.fieldPaths=" + $0 }.joined(separator: "&") }
    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    /// The stored token is an FCM registration token (same kind the Android app writes); FCM routes it to APNs.
    static var currentEnv: String { "fcm" }
    static var appVersion: String {
        let i = Bundle.main.infoDictionary
        return (i?["CFBundleShortVersionString"] as? String ?? "0") + "(" + (i?["CFBundleVersion"] as? String ?? "0") + ")"
    }
}

@MainActor final class PushSync {
    private let store: PushStoring, writer: PushWriting, env: String, appVersion: String, now: () -> Date
    init(store: PushStoring, writer: PushWriting, env: String = DevicePayload.currentEnv, appVersion: String = DevicePayload.appVersion, now: @escaping () -> Date = Date.init) {
        self.store = store; self.writer = writer; self.env = env; self.appVersion = appVersion; self.now = now
    }
    func tokenArrived(_ token: String, uid: String?) async -> PushOutcome {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .skipped("no token") }
        store.pendingToken = t
        return await sync(uid: uid)
    }
    /// Triggers: token arrival, launch, sign-in, retry.
    func sync(uid: String?) async -> PushOutcome {

        guard let t = store.pendingToken, !t.isEmpty else { return .skipped("no token") }
        guard let uid else { return .skipped("guest") }
        // Gate: this installId moves to a new uid only after the old owner's doc is confirmed deleted.
        let pd = store.pendingDelete
        if let pd, pd.uid != uid { return .skipped("old owner device doc not deleted") }
        let prev = store.written
        if let prev, prev.uid != uid { return .skipped("previous owner not signed out") }
        let w = PushWritten(uid: uid, token: t, env: env, appVersion: appVersion)
        if prev == w { return .skipped("unchanged") }
        guard await writer.upsert(uid: uid, installId: store.installId, fields: DevicePayload.fields(token: t, env: env, appVersion: appVersion, now: now())) else { return .failed }
        if pd != nil { store.pendingDelete = nil }   // same uid re-registered: stale doc overwritten
        store.written = w
        return .written
    }
    /// Same uid signed in at launch with nothing to register (permission off): finish the owed delete.
    func retryPendingDelete(uid: String?) async -> PushOutcome {
        guard let pd = store.pendingDelete else { return .skipped("none pending") }
        guard let uid, pd.uid == uid else { return .skipped("pending is for another uid") }
        guard await writer.delete(uid: pd.uid, installId: pd.installId) else { return .failed }
        store.pendingDelete = nil; return .deleted
    }
    /// `deleter` is bound to credentials captured BEFORE the wipe (refreshed if expired). Host wraps in ~5s timeout (timeout = false).
    /// Pending is persisted first so crash/timeout/offline leaves a record. Local sign-out proceeds regardless.
    func onSignOut(uid: String?, deleter: PushWriting? = nil) async -> PushOutcome {
        guard let uid else { return .skipped("guest") }
        let had = (store.written?.uid == uid) || (store.pendingDelete?.uid == uid)
        guard had else { return .skipped("nothing registered for this uid") }
        let id = store.installId
        store.pendingDelete = PendingDelete(uid: uid, installId: id); store.written = nil
        guard await (deleter ?? writer).delete(uid: uid, installId: id) else { return .failed }
        store.pendingDelete = nil; return .deleted
    }
    /// Delete-account: this device doc first; on failure return .failed so the host aborts and the user can retry.
    func onDeleteAccount(uid: String?) async -> PushOutcome {
        guard let uid else { return .skipped("guest") }
        guard await writer.delete(uid: uid, installId: store.installId) else { return .failed }
        store.written = nil; store.pendingDelete = nil; return .deleted
    }
    static func retryDelay(_ attempt: Int) -> TimeInterval { attempt <= 0 ? 5 : attempt == 1 ? 30 : attempt == 2 ? 180 : 600 }
}


enum PromptTrigger { case signedIn, firstAddToBag, launch, orderPlaced, other }
enum PushPrompt {   // unchanged from v2
    static let cooldown: TimeInterval = 30 * 24 * 3600
    static func shouldShow(status: UNAuthorizationStatus, trigger: PromptTrigger, now: Date, lastPromptAt: Date?, firstLaunch: Bool) -> Bool {
        guard status == .notDetermined, trigger != .other else { return false }
        if firstLaunch, trigger != .launch { return false }
        if let l = lastPromptAt, now.timeIntervalSince(l) < cooldown { return false }
        return true
    }
}

// ---- UIKit glue (device-only, not unit-tested) ----

final class DefaultsPushStore: PushStoring {
    private let d = UserDefaults.standard
    var installId: String {
        if let s = d.string(forKey: "djpush.install") { return s }
        let n = UUID().uuidString; d.set(n, forKey: "djpush.install"); return n
    }
    var written: PushWritten? {
        get { guard let u = d.string(forKey: "djpush.w.uid"), let t = d.string(forKey: "djpush.w.tok"),
                    let e = d.string(forKey: "djpush.w.env"), let v = d.string(forKey: "djpush.w.ver") else { return nil }
              return PushWritten(uid: u, token: t, env: e, appVersion: v) }
        set { let ks = ["djpush.w.uid", "djpush.w.tok", "djpush.w.env", "djpush.w.ver"]
              if let n = newValue { d.set(n.uid, forKey: ks[0]); d.set(n.token, forKey: ks[1]); d.set(n.env, forKey: ks[2]); d.set(n.appVersion, forKey: ks[3]) }
              else { ks.forEach { d.removeObject(forKey: $0) } } }
    }
    var pendingDelete: PendingDelete? {
        get { guard let u = d.string(forKey: "djpush.pd.uid"), let i = d.string(forKey: "djpush.pd.id") else { return nil }; return PendingDelete(uid: u, installId: i) }
        set { if let n = newValue { d.set(n.uid, forKey: "djpush.pd.uid"); d.set(n.installId, forKey: "djpush.pd.id") }
              else { d.removeObject(forKey: "djpush.pd.uid"); d.removeObject(forKey: "djpush.pd.id") } }
    }
    var lastPromptAt: Date? { get { d.object(forKey: "djpush.prompt") as? Date } set { d.set(newValue, forKey: "djpush.prompt") } }
    var pendingToken: String? { get { d.string(forKey: "djpush.pending") } set { d.set(newValue, forKey: "djpush.pending") } }
}

struct FailingWriter: PushWriting {
    func upsert(uid: String, installId: String, fields: [String: String]) async -> Bool { false }
    func delete(uid: String, installId: String) async -> Bool { false }
}

/// Firestore REST writer for users/{uid}/devices/{installId}. Short timeouts; 404 on delete counts as success.
struct DeviceWriter: PushWriting {
    let tok: () async throws -> String
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4; c.timeoutIntervalForResource = 6; c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    private func url(_ uid: String, _ id: String, mask: String) -> URL? {
        let base = "https://firestore.googleapis.com/v1/projects/" + AccountConfig.projectId + "/databases/(default)/documents/users/" + uid + "/devices/" + id
        return URL(string: mask.isEmpty ? base : base + "?" + mask)
    }
    private func call(_ method: String, _ u: URL, body: Data?) async -> Bool {
        guard let t = try? await tok() else { return false }
        var r = URLRequest(url: u, timeoutInterval: 4)
        r.httpMethod = method
        r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
        r.setValue("com.dressjet.shop", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let (_, resp) = try? await Self.session.data(for: r), let code = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return code < 300 || (method == "DELETE" && code == 404)
    }
    func upsert(uid: String, installId: String, fields: [String: String]) async -> Bool {
        guard let u = url(uid, installId, mask: DevicePayload.mask(Array(fields.keys))),
              let b = try? JSONSerialization.data(withJSONObject: DevicePayload.body(fields)) else { return false }
        return await call("PATCH", u, body: b)
    }
    func delete(uid: String, installId: String) async -> Bool {
        guard let u = url(uid, installId, mask: "") else { return false }
        return await call("DELETE", u, body: nil)
    }
}

enum PushFirebase {
    /// No GoogleService-Info.plist: public client config, same values as the Android app and AccountConfig.
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        let o = FirebaseOptions(googleAppID: "1:1061618560989:ios:816618c78362023b821034", gcmSenderID: "1061618560989")
        o.apiKey = AccountConfig.apiKey
        o.projectID = AccountConfig.projectId
        o.bundleID = "com.dressjet.shop"
        FirebaseApp.configure(options: o)
    }
}

final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushFirebase.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in await PushCoordinator.shared.onLaunch() }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { tok, _ in
            guard let tok else { return }
            Task { @MainActor in await PushCoordinator.shared.tokenArrived(tok) }
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await PushCoordinator.shared.tokenArrived(fcmToken) }
    }
    // Foreground messages are not displayed (same as Android): no willPresent override.
}

@MainActor final class PushCoordinator {
    static let shared = PushCoordinator()
    let store = DefaultsPushStore()
    lazy var sync = PushSync(store: store, writer: Account.shared.deviceWriter())
    private var attempt = 0
    private var firstLaunchHandled: Bool {
        get { UserDefaults.standard.bool(forKey: "djpush.launched") }
        set { UserDefaults.standard.set(newValue, forKey: "djpush.launched") }
    }
    private func status() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    private func granted(_ s: UNAuthorizationStatus) -> Bool { s == .authorized || s == .provisional || s == .ephemeral }

    func onLaunch() async {
        let s = await status()
        if granted(s) { UIApplication.shared.registerForRemoteNotifications() }
        else {
            // Permission off (or never asked): never register or keep a token; only finish an owed delete.
            store.pendingToken = nil
            _ = await sync.retryPendingDelete(uid: Account.shared.uid)
        }
        // Build 320: ask on first open (system dialog) once the UI is up; iOS only ever shows it once.
        if s == .notDetermined {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await maybePrompt(.launch)
        }
        firstLaunchHandled = true
    }
    func tokenArrived(_ token: String) async {
        guard granted(await status()) else { store.pendingToken = nil; return }
        handle(await sync.tokenArrived(token, uid: Account.shared.uid))
    }
    func afterSignIn() async {
        await maybePrompt(.signedIn)
        if granted(await status()) { UIApplication.shared.registerForRemoteNotifications() }
        handle(await sync.sync(uid: Account.shared.uid))
    }
    func onOrderPlaced() { Task { await maybePrompt(.orderPlaced) } }
    func onBagChanged() { Task { await maybePrompt(.firstAddToBag) } }

    /// System dialog on first launch, after sign-in, first bag change or a finished order; 30-day cooldown.
    private func maybePrompt(_ t: PromptTrigger) async {
        let s = await status()
        guard PushPrompt.shouldShow(status: s, trigger: t, now: Date(), lastPromptAt: store.lastPromptAt, firstLaunch: !firstLaunchHandled) else { return }
        store.lastPromptAt = Date()
        if (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) == true {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    /// Menu "Sign out": local marker first, credentials captured before the wipe, wipe ALWAYS runs.
    func signOut(wipe: @escaping () -> Void) async {
        let uid = Account.shared.uid
        let bound: PushWriting = (try? await Account.shared.deviceWriterSnapshot()) ?? FailingWriter()
        _ = await raceOrTimeout(seconds: 5) { _ = await self.sync.onSignOut(uid: uid, deleter: bound); return true }
        wipe()
    }
    /// Best effort, short timeout; never blocks account deletion (marker stays if it fails).
    func deleteAccountDevice() async {
        let uid = Account.shared.uid
        _ = await raceOrTimeout(seconds: 5) { _ = await self.sync.onDeleteAccount(uid: uid); return true }
    }
    func accountDeleted(uid: String?) {
        if let uid, store.pendingDelete?.uid == uid { store.pendingDelete = nil }
    }
    private func handle(_ o: PushOutcome) {
        guard o == .failed, attempt < 4 else { attempt = 0; return }
        let n = attempt; attempt += 1
        Task { try? await Task.sleep(nanoseconds: UInt64(PushSync.retryDelay(n) * 1e9)); await afterSignInRetry() }
    }
    private func afterSignInRetry() async { handle(await sync.sync(uid: Account.shared.uid)) }
}

private final class RaceOnce: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    private let cont: CheckedContinuation<Bool, Never>
    init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
    func finish(_ v: Bool) { lock.lock(); let first = !done; done = true; lock.unlock(); if first { cont.resume(returning: v) } }
}
/// Runs work; returns false if it didn't finish in time. No task group: the first result wins, the other is ignored.
func raceOrTimeout(seconds: Double, _ work: @escaping @Sendable () async -> Bool) async -> Bool {
    await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
        let once = RaceOnce(c)
        Task { once.finish(await work()) }
        Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); once.finish(false) }
    }
}
