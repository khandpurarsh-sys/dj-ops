// DJ Ops native shell: maps the app's WebAuthn phone-unlock calls onto a
// native Face ID / device-unlock plugin backed by an iOS Keychain key.
// Loaded only in the Capacitor build; the web app is untouched.
//
// Security model (matches the app's own "prf" mode): on enrollment the
// plugin generates a random 256-bit key in the iOS Keychain, readable only
// after device user verification (Face ID, falling back to device passcode,
// exactly like WebAuthn userVerification). On unlock the app receives that
// key as the PRF output and derives its wrapping key with HKDF - the ECDH
// private key that decrypts app data stays AES-GCM-wrapped in local storage
// and can only be unwrapped after a successful Face ID prompt. No passphrase
// is stored anywhere, and no wrapping key is stored in web storage (the
// app's weaker "gate" fallback never activates here).
(function () {
  try {
    var C = window.Capacitor;
    if (!C || !C.isNativePlatform || !C.isNativePlatform()) return;
    var P = C.Plugins && C.Plugins.DjOpsUnlock;
    if (!P) return;

    function b64(buf) { return btoa(String.fromCharCode.apply(null, new Uint8Array(buf))); }
    function ub64(s) { return Uint8Array.from(atob(s), function (c) { return c.charCodeAt(0); }); }
    function randBytes(n) { var u = new Uint8Array(n); crypto.getRandomValues(u); return u; }
    function authData() {
      // 32-byte rpId hash placeholder + flags byte (UP|UV set) + 4-byte counter
      var u = new Uint8Array(37); u[32] = 0x05; return u.buffer;
    }

    if (!window.PublicKeyCredential) {
      window.PublicKeyCredential = function () {};
    }
    Object.defineProperty(window.PublicKeyCredential, 'isUserVerifyingPlatformAuthenticatorAvailable', {
      value: function () {
        return P.canAuthenticate().then(function (r) { return !!r.available; }).catch(function () { return false; });
      }
    });

    var creds = {
      create: function (opts) {
        if (!opts || !opts.publicKey) return Promise.reject(new Error('Unsupported credential request'));
        return P.enroll().then(function () {
          var id = randBytes(32);
          return {
            id: b64(id), rawId: id.buffer, type: 'public-key',
            response: { clientDataJSON: new ArrayBuffer(0), attestationObject: new ArrayBuffer(0) },
            getClientExtensionResults: function () { return { prf: { enabled: true } }; }
          };
        });
      },
      get: function (opts) {
        if (!opts || !opts.publicKey) return Promise.reject(new Error('Unsupported credential request'));
        var wantsPrf = !!(opts.publicKey.extensions && opts.publicKey.extensions.prf);
        return P.unlock().then(function (r) {
          var id = randBytes(32);
          return {
            id: b64(id), rawId: id.buffer, type: 'public-key',
            response: { authenticatorData: authData(), clientDataJSON: new ArrayBuffer(0), signature: new ArrayBuffer(0) },
            getClientExtensionResults: function () {
              return wantsPrf ? { prf: { results: { first: ub64(r.key).buffer } } } : {};
            }
          };
        });
      }
    };
    Object.defineProperty(navigator, 'credentials', { value: creds, configurable: true });
  } catch (e) { /* leave browser defaults in place */ }
})();
