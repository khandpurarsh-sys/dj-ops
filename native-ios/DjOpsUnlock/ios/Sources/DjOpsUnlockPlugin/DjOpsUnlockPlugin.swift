import Foundation
import Capacitor
import LocalAuthentication
import Security

@objc(DjOpsUnlockPlugin)
public class DjOpsUnlockPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DjOpsUnlock"
    public let jsName = "DjOpsUnlock"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "canAuthenticate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enroll", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "unlock", returnType: CAPPluginReturnPromise)
    ]

    private let service = "com.arsh.djops.unlock"
    private let account = "gate-key"

    @objc func canAuthenticate(_ call: CAPPluginCall) {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
        call.resolve(["available": ok])
    }

    @objc func enroll(_ call: CAPPluginCall) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            call.reject("Could not generate key"); return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
            call.reject("Could not create access control"); return
        }
        var attrs = base
        attrs[kSecValueData as String] = Data(bytes)
        attrs[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecSuccess { call.resolve() } else { call.reject("Keychain save failed (\(status))") }
    }

    @objc func unlock(_ call: CAPPluginCall) {
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock DJ Ops") { ok, err in
            guard ok else {
                call.reject(err?.localizedDescription ?? "Unlock cancelled"); return
            }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.service,
                kSecAttrAccount as String: self.account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: ctx
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                call.resolve(["key": data.base64EncodedString()])
            } else {
                call.reject("Phone unlock is not set up on this device")
            }
        }
    }
}
