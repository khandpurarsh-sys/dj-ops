import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

/** Shopify Customer Account API (read-only past orders). Public mobile client, PKCE.
 *  CLIENT_ID is a public identifier, not a secret. */
enum ShopifyCfg {
    static let clientId = "0cce356f-fe99-4ca9-a001-6d950e5649c0"
    static let shopId = "64343474221"
    static let authorize = "https://shopify.com/authentication/\(shopId)/oauth/authorize"
    static let token = "https://shopify.com/authentication/\(shopId)/oauth/token"
    static let graphql = "https://shopify.com/\(shopId)/account/customer/api/2026-10/graphql"
    static let scheme = "shop.\(shopId).app"
    static let redirect = "shop.\(shopId).app://callback"
    static var configured: Bool { !clientId.hasPrefix("__") }
}

struct PastOrder: Identifiable {
    let id = UUID()
    let name: String, date: String, total: String, status: String, items: [String], url: String
}

@MainActor final class OrdersStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OrdersStore()
    @Published var connected = false
    @Published var loading = false
    @Published var message: String?
    @Published var orders: [PastOrder]?

    private var access = ""
    private var refresh = ""
    private var expiresAt = Date.distantPast
    private let d = UserDefaults.standard

    override init() {
        super.init()
        refresh = d.string(forKey: "djorders.rt") ?? ""
        connected = !refresh.isEmpty
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }

    func signIn(emailHint: String) async {
        guard ShopifyCfg.configured else { message = "Past orders are not set up in this build."; return }
        message = nil; loading = true
        defer { loading = false }
        do {
            let verifier = Self.randomString(64)
            let state = Self.randomString(16)
            let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
            var c = URLComponents(string: ShopifyCfg.authorize)!
            var q: [URLQueryItem] = [
                .init(name: "scope", value: "openid email customer-account-api:full"),
                .init(name: "client_id", value: ShopifyCfg.clientId),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: ShopifyCfg.redirect),
                .init(name: "state", value: state),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
            ]
            if !emailHint.isEmpty { q.append(.init(name: "login_hint", value: emailHint)) }
            c.queryItems = q
            let items: [URLQueryItem] = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: ShopifyCfg.scheme) { url, err in
                    if let err { cont.resume(throwing: err); return }
                    cont.resume(returning: url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
                }
                s.presentationContextProvider = self
                s.prefersEphemeralWebBrowserSession = false
                if !s.start() { cont.resume(throwing: URLError(.cannotLoadFromNetwork)) }
            }
            guard let code = items.first(where: { $0.name == "code" })?.value,
                  items.first(where: { $0.name == "state" })?.value == state else { message = "Sign-in did not complete. Try again."; return }
            let r = try await form(ShopifyCfg.token, ["grant_type": "authorization_code", "client_id": ShopifyCfg.clientId,
                                                      "redirect_uri": ShopifyCfg.redirect, "code": code, "code_verifier": verifier])
            take(r)
            connected = true
            await load()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // cancelled by the person
        } catch {
            message = "Could not finish sign-in. Please try again."
        }
    }

    func refreshOrders() async { guard connected, !loading else { return }; loading = true; message = nil; await load(); loading = false }

    func signOut() {
        access = ""; refresh = ""; expiresAt = .distantPast; connected = false; orders = nil; message = nil
        d.removeObject(forKey: "djorders.rt")
    }

    private func take(_ o: [String: Any]) {
        access = (o["access_token"] as? String) ?? ""
        if let r = o["refresh_token"] as? String { refresh = r; d.set(r, forKey: "djorders.rt") }
        let ex = (o["expires_in"] as? Double) ?? 3600
        expiresAt = Date().addingTimeInterval(ex - 60)
    }

    private func token() async throws -> String {
        if !access.isEmpty && Date() < expiresAt { return access }
        let r = try await form(ShopifyCfg.token, ["grant_type": "refresh_token", "client_id": ShopifyCfg.clientId, "refresh_token": refresh])
        take(r)
        return access
    }

    private func load() async {
        do {
            let q = "{ customer { orders(first: 30, sortKey: PROCESSED_AT, reverse: true) { nodes { name processedAt cancelledAt financialStatus fulfillmentStatus statusPageUrl totalPrice { amount currencyCode } lineItems(first: 10) { nodes { title quantity } } } } } }"
            var req = URLRequest(url: URL(string: ShopifyCfg.graphql)!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(try await token(), forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["query": q])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { signOut(); message = "Please sign in again to see your orders."; return }
            guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { message = "Could not load orders right now."; return }
            if let errs = j["errors"] as? [Any], !errs.isEmpty { message = "Could not load orders right now."; return }
            let nodes = (((j["data"] as? [String: Any])?["customer"] as? [String: Any])?["orders"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            orders = nodes.map { n in
                let tp = n["totalPrice"] as? [String: Any] ?? [:]
                let cur = (tp["currencyCode"] as? String) ?? ""
                let amtS = (tp["amount"] as? String) ?? ""
                let amt = Double(amtS).map { String(format: "%.2f", $0) } ?? amtS
                let li = ((n["lineItems"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
                let items = li.map { "\(($0["quantity"] as? Int) ?? 1) x \(($0["title"] as? String) ?? "")" }
                let cancelled = !(n["cancelledAt"] is NSNull) && n["cancelledAt"] != nil
                let ful = Self.nice((n["fulfillmentStatus"] as? String) ?? "")
                let status = cancelled ? "Cancelled" : (ful.isEmpty ? Self.nice((n["financialStatus"] as? String) ?? "") : ful)
                return PastOrder(name: (n["name"] as? String) ?? "", date: String(((n["processedAt"] as? String) ?? "").prefix(10)),
                                 total: (cur == "INR" ? "Rs. " : cur + " ") + amt, status: status, items: items, url: (n["statusPageUrl"] as? String) ?? "")
            }
        } catch {
            message = "Could not load orders right now."
        }
    }

    private func form(_ url: String, _ p: [String: String]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = p.map { Self.enc($0.key) + "=" + Self.enc($0.value) }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            if (resp as? HTTPURLResponse)?.statusCode == 400 { signOut() }
            throw URLError(.badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func nice(_ s: String) -> String {
        let t = s.lowercased().replacingOccurrences(of: "_", with: " ")
        return t.isEmpty ? "" : String(t.prefix(1)).uppercased() + String(t.dropFirst())
    }
    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? s
    }
    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func randomString(_ n: Int) -> String {
        let cs = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        for _ in 0..<n { out.append(cs[Int.random(in: 0..<cs.count)]) }
        return out
    }
}

struct PastOrdersSheet: View {
    @ObservedObject private var store = OrdersStore.shared
    @ObservedObject private var acct = Account.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.connected {
                        Text("To see your past orders, sign in with the email address you used when you ordered. Shopify sends a code to that email.")
                            .font(Dj.assistant(14)).lineSpacing(5).foregroundStyle(Dj.ink2)
                        Button { Task { await store.signIn(emailHint: acct.email) } } label: {
                            Text(store.loading ? "Opening…" : "Sign in with email")
                                .font(Dj.assistant(14, weight: .medium)).foregroundStyle(Dj.navy)
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Dj.navy.opacity(0.35), lineWidth: 1))
                        }.buttonStyle(.plain).disabled(store.loading)
                    } else if store.loading && store.orders == nil {
                        Text("Loading…").font(Dj.assistant(13)).foregroundStyle(Dj.ink3)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let list = store.orders {
                        if list.isEmpty {
                            Text("No orders found for this email.").font(Dj.assistant(14)).foregroundStyle(Dj.ink2)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        }
                        ForEach(list) { o in OrderCard(order: o) }
                    }
                    if let m = store.message { Text(m).font(Dj.assistant(12)).foregroundStyle(Dj.ink2) }
                    if store.connected {
                        Button("Disconnect") { store.signOut() }
                            .font(Dj.assistant(12)).foregroundStyle(Dj.ink3).padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle("Past orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if store.connected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Refresh") { Task { await store.refreshOrders() } }
                            .font(Dj.assistant(13, weight: .medium)).foregroundStyle(Dj.navy)
                    }
                }
            }
        }
        .task { if store.connected && store.orders == nil { await store.refreshOrders() } }
    }
}

/** 234 (Arsh 10:36 PM: "better view ui for past orders"): hairline card per order -
 *  serif order number, quiet gold/grey status pill, date + total, items, tracking link. */
private struct OrderCard: View {
    let order: PastOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(order.name).font(Dj.cormorant(21)).foregroundStyle(Dj.navy)
                Spacer()
                StatusPill(status: order.status)
            }
            Spacer().frame(height: 3)
            Text(order.date + "  ·  " + order.total)
                .font(Dj.assistant(12.5, weight: .medium)).foregroundStyle(Dj.ink2)
            if !order.items.isEmpty {
                Spacer().frame(height: 9)
                ForEach(order.items, id: \.self) {
                    Text($0).font(Dj.assistant(13)).lineSpacing(5).foregroundStyle(Dj.ink2)
                }
            }
            if let u = URL(string: order.url), !order.url.isEmpty {
                Spacer().frame(height: 9)
                Rectangle().fill(Dj.navy.opacity(0.10)).frame(height: 1)
                Spacer().frame(height: 9)
                Link("Track / details →", destination: u)
                    .font(Dj.assistant(13, weight: .medium)).foregroundStyle(Dj.navy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Dj.navy.opacity(0.10), lineWidth: 1))
    }
}

private struct StatusPill: View {
    let status: String
    var body: some View {
        let s = status.lowercased()
        let cancelled = s.contains("cancel")
        let good = s.contains("fulfill") || s.contains("deliver") || s.contains("paid")
        let bg: Color = cancelled ? Color(red: 0.953, green: 0.827, blue: 0.812)
            : good ? Color(red: 0.929, green: 0.902, blue: 0.827) : Color.clear
        let ink: Color = cancelled ? Color(red: 0.541, green: 0.173, blue: 0.133)
            : bg == .clear ? Dj.ink2 : Dj.navy
        Text(status.isEmpty ? "Placed" : status)
            .font(Dj.assistant(10.5, weight: .medium)).foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(bg == .clear ? Dj.navy.opacity(0.10) : Color.clear, lineWidth: 1))
    }
}
