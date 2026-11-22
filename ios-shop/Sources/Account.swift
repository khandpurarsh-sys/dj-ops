import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

/** Public (non-secret) Firebase client config. Filled from the Firebase console. */
enum AccountConfig {
    static let projectId = "dressjet-shop"
    static let apiKey = "AIzaSyAkBpvx0wL7DqYpD1Gb9skYbR-a2CqcMrQ"
    static let iosClientId = "1061618560989-abecpm3l3er9454te13uu7v8ibpdij5m.apps.googleusercontent.com"
    static let reversedClientId = "com.googleusercontent.apps.1061618560989-abecpm3l3er9454te13uu7v8ibpdij5m"
    static var configured: Bool {
        !projectId.hasPrefix("__") && !apiKey.hasPrefix("__") && !iosClientId.hasPrefix("__") && !reversedClientId.hasPrefix("__")
    }
}

/** Optional account (Sign in with Apple, Google). Guest use is unchanged. Signed in: the bag and
 *  saved details live in the person's own Firestore document (users/{uid}), so they are not only
 *  on the phone. Firebase Auth + Firestore over REST (no Firebase SDK). On the device: the refresh token. */
@MainActor final class Account: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Account()

    @Published private(set) var uid: String? = nil
    @Published private(set) var email = ""
    @Published var name = ""
    @Published var phone = ""
    @Published var address = ""
    @Published private(set) var busy = false
    @Published var message: String? = nil

    private let d = UserDefaults.standard
    private var idToken = ""
    private var refreshToken = ""
    private var expiresAt = Date.distantPast
    private weak var bag: Bag?
    private var pushTask: Task<Void, Never>?
    private var appleNonce = ""

    var signedIn: Bool { uid != nil }

    private override init() {
        super.init()
        refreshToken = d.string(forKey: "djacct.rt") ?? ""
        uid = d.string(forKey: "djacct.uid")
        email = d.string(forKey: "djacct.email") ?? ""
        name = d.string(forKey: "djacct.name") ?? ""
        phone = d.string(forKey: "djacct.phone") ?? ""
        address = d.string(forKey: "djacct.address") ?? ""
    }

    func attach(_ b: Bag) {
        bag = b
        if signedIn && !refreshToken.isEmpty { Task { try? await syncDown() } }
    }

    func bagChanged() { if signedIn { pushLater() } }

    func saveDetails(name n: String, phone ph: String, address a: String) {
        name = n; phone = ph; address = a
        d.set(n, forKey: "djacct.name"); d.set(ph, forKey: "djacct.phone"); d.set(a, forKey: "djacct.address")
        if signedIn { pushLater() }
    }

    // MARK: sign-in

    func prepareApple(_ req: ASAuthorizationAppleIDRequest) {
        appleNonce = Self.randomString(32)
        req.requestedScopes = [.fullName, .email]
        req.nonce = Self.sha256(appleNonce)
    }

    func finishApple(_ result: Result<ASAuthorization, Error>) async {
        guard AccountConfig.configured else { message = "Sign-in is not set up in this build."; return }
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code == .canceled { return }
            message = "Could not sign in. Please try again."
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokData = cred.identityToken, let tok = String(data: tokData, encoding: .utf8) else {
                message = "Could not sign in. Please try again."; return
            }
            if let fn = cred.fullName, name.isEmpty {
                name = [fn.givenName, fn.familyName].compactMap { $0 }.joined(separator: " ")
            }
            busy = true; message = nil
            defer { busy = false }
            do { try await exchange(provider: "apple.com", idToken: tok, nonce: appleNonce) }
            catch { message = "Could not sign in. Please try again." }
        }
    }

    func signInWithGoogle() async {
        guard AccountConfig.configured else { message = "Sign-in is not set up in this build."; return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let verifier = Self.randomString(64)
            let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
            let redirect = AccountConfig.reversedClientId + ":/oauth2redirect"
            var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            c.queryItems = [
                .init(name: "client_id", value: AccountConfig.iosClientId),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "openid email profile"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
            ]
            let code: String = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: AccountConfig.reversedClientId) { url, err in
                    if let err { cont.resume(throwing: err); return }
                    let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
                    if let code = items?.first(where: { $0.name == "code" })?.value { cont.resume(returning: code) }
                    else { cont.resume(throwing: URLError(.badServerResponse)) }
                }
                s.presentationContextProvider = self
                s.prefersEphemeralWebBrowserSession = false
                if !s.start() { cont.resume(throwing: URLError(.cannotLoadFromNetwork)) }
            }
            var tr = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            tr.httpMethod = "POST"
            tr.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            tr.httpBody = Self.form(["code": code, "client_id": AccountConfig.iosClientId, "code_verifier": verifier,
                                     "redirect_uri": redirect, "grant_type": "authorization_code"]).data(using: .utf8)
            let (td, tresp) = try await URLSession.shared.data(for: tr)
            guard (tresp as? HTTPURLResponse)?.statusCode == 200,
                  let tj = try JSONSerialization.jsonObject(with: td) as? [String: Any],
                  let idt = tj["id_token"] as? String else { throw URLError(.badServerResponse) }
            try await exchange(provider: "google.com", idToken: idt, nonce: nil)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // cancelled by the person: nothing to say
        } catch {
            message = "Could not sign in. Please try again."
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }

    private func exchange(provider: String, idToken tok: String, nonce: String?) async throws {
        var pb = "id_token=" + Self.enc(tok) + "&providerId=" + provider
        if let nonce { pb += "&nonce=" + Self.enc(nonce) }
        let body: [String: Any] = ["postBody": pb, "requestUri": "http://localhost",
                                   "returnIdpCredential": true, "returnSecureToken": true]
        let o = try await post("https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=" + AccountConfig.apiKey,
                               json: body)
        guard let id = o["idToken"] as? String, let rt = o["refreshToken"] as? String, let lid = o["localId"] as? String
        else { throw URLError(.badServerResponse) }
        idToken = id; refreshToken = rt
        expiresAt = Date().addingTimeInterval((Double(o["expiresIn"] as? String ?? "3600") ?? 3600) - 60)
        uid = lid; email = (o["email"] as? String) ?? ""
        if name.isEmpty { name = (o["displayName"] as? String) ?? "" }
        d.set(rt, forKey: "djacct.rt"); d.set(lid, forKey: "djacct.uid"); d.set(email, forKey: "djacct.email")
        try await syncDown()
    }

    func signOut() {
        pushTask?.cancel()
        uid = nil; email = ""; idToken = ""; refreshToken = ""; message = nil
        ["djacct.rt", "djacct.uid", "djacct.email"].forEach { d.removeObject(forKey: $0) }
    }

    func deleteAccount() async {
        busy = true
        defer { busy = false }
        do {
            guard let u = uid else { return }
            let t = try await token()
            _ = try await fs("DELETE", u, nil, t)
            _ = try await post("https://identitytoolkit.googleapis.com/v1/accounts:delete?key=" + AccountConfig.apiKey,
                               json: ["idToken": t])
            signOut()
            name = ""; phone = ""; address = ""
            ["djacct.name", "djacct.phone", "djacct.address"].forEach { d.removeObject(forKey: $0) }
        } catch {
            message = "Could not delete the account. Sign in again and retry."
        }
    }

    // MARK: sync

    private func syncDown() async throws {
        guard let u = uid else { return }
        let t = try await token()
        if let data = try await fs("GET", u, nil, t),
           let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let f = o["fields"] as? [String: Any] {
            func s(_ k: String) -> String { ((f[k] as? [String: Any])?["stringValue"] as? String) ?? "" }
            if !s("name").isEmpty { name = s("name") }
            if !s("phone").isEmpty { phone = s("phone") }
            if !s("address").isEmpty { address = s("address") }
            bag?.mergeRemote(s("bag"))
        }
        d.set(name, forKey: "djacct.name"); d.set(phone, forKey: "djacct.phone"); d.set(address, forKey: "djacct.address")
        try await push()
    }

    private func pushLater() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            try? await self?.push()
        }
    }

    private func push() async throws {
        guard let u = uid else { return }
        func sv(_ v: String) -> [String: Any] { ["stringValue": v] }
        let body: [String: Any] = ["fields": ["bag": sv(bag?.json ?? "[]"), "name": sv(name), "phone": sv(phone),
                                              "address": sv(address), "updatedAt": sv(String(Int(Date().timeIntervalSince1970 * 1000)))]]
        _ = try await fs("PATCH", u, try JSONSerialization.data(withJSONObject: body), try await token())
    }

    // MARK: REST

    private func token() async throws -> String {
        if !idToken.isEmpty && Date() < expiresAt { return idToken }
        var r = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=" + AccountConfig.apiKey)!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("com.dressjet.shop", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        r.httpBody = Self.form(["grant_type": "refresh_token", "refresh_token": refreshToken]).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["id_token"] as? String else { throw URLError(.userAuthenticationRequired) }
        idToken = id
        if let rt = o["refresh_token"] as? String { refreshToken = rt; d.set(rt, forKey: "djacct.rt") }
        expiresAt = Date().addingTimeInterval((Double(o["expires_in"] as? String ?? "3600") ?? 3600) - 60)
        return id
    }

    /** Returns the body, or nil on 404 (no document yet). */
    private func fs(_ method: String, _ uid: String, _ body: Data?, _ tok: String) async throws -> Data? {
        let u = "https://firestore.googleapis.com/v1/projects/" + AccountConfig.projectId + "/databases/(default)/documents/users/" + uid
        var r = URLRequest(url: URL(string: u)!, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue("Bearer " + tok, forHTTPHeaderField: "Authorization")
        r.setValue("com.dressjet.shop", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code < 300 else { throw URLError(.badServerResponse) }
        return data
    }

    private func post(_ url: String, json: [String: Any]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("com.dressjet.shop", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        r.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let code = (resp as? HTTPURLResponse)?.statusCode, code < 300 else { throw URLError(.badServerResponse) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: helpers

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? s
    }
    private static func form(_ p: [String: String]) -> String { p.map { enc($0.key) + "=" + enc($0.value) }.joined(separator: "&") }
    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func randomString(_ n: Int) -> String {
        let cs = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        for _ in 0..<n { out.append(cs[Int.random(in: 0..<cs.count)]) }
        return out
    }
    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/** Menu section: sign in (Apple + Google), saved details, sign out, delete account. */
struct AccountSection: View {
    @ObservedObject private var acct = Account.shared
    @State private var details = false
    @State private var confirmDelete = false
    @State private var ordersOpen = false
    @State private var n = ""
    @State private var ph = ""
    @State private var ad = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACCOUNT")
                .font(Dj.assistant(9, weight: .semibold)).tracking(2.25)
                .foregroundStyle(Color(red: 0x8A/255, green: 0x75/255, blue: 0x3E/255))
                .padding(.top, 26).padding(.bottom, 8)
            if !acct.signedIn {
                SignInWithAppleButton(.signIn,
                    onRequest: { acct.prepareApple($0) },
                    onCompletion: { r in Task { await acct.finishApple(r) } })
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 46)
                    .disabled(acct.busy)
                Button { Task { await acct.signInWithGoogle() } } label: {
                    Text(acct.busy ? "Signing in…" : "Sign in with Google")
                        .font(Dj.assistant(15, weight: .medium)).foregroundStyle(Dj.navy)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Dj.navy.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(acct.busy).padding(.top, 10)
            } else {
                Text(acct.email).font(Dj.assistant(12)).foregroundStyle(Dj.navy.opacity(0.8)).padding(.bottom, 4)
                row("Saved details") { n = acct.name; ph = acct.phone; ad = acct.address; details = true }
                row("Sign out") { acct.signOut() }
                row("Delete account and saved data") { confirmDelete = true }
            }
            row("Past orders") { ordersOpen = true }
            if let m = acct.message {
                Text(m).font(Dj.assistant(12)).foregroundStyle(Dj.navy.opacity(0.8)).padding(.top, 8)
            }
        }
        .sheet(isPresented: $details) {
            NavigationStack {
                Form {
                    TextField("Name", text: $n)
                    TextField("Phone", text: $ph).keyboardType(.phonePad)
                    TextField("Delivery address", text: $ad, axis: .vertical)
                }
                .navigationTitle("Saved details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { details = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            acct.saveDetails(name: n.trimmingCharacters(in: .whitespaces), phone: ph.trimmingCharacters(in: .whitespaces),
                                             address: ad.trimmingCharacters(in: .whitespaces))
                            details = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $ordersOpen) { PastOrdersSheet() }
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await acct.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your saved bag and details from your account. Orders already placed are not affected.")
        }
    }

    private func row(_ label: String, _ action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(label).font(Dj.assistant(15)).foregroundStyle(Dj.navy)
                    Spacer()
                    Text("→").font(.system(size: 14)).foregroundStyle(Dj.navy)
                }
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Dj.navy.opacity(0.075)).frame(height: 1)
        }
    }
}
