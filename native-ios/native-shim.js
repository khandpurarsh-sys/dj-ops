// DJ Ops native shell: maps the app's WebAuthn phone-unlock calls onto the
// native Face ID / device-unlock plugin. Loaded only in the Capacitor build;
// the web app is untouched. The app's own code keeps its "phone lock gate"
// mode: Face ID is required before the locally stored wrapping key is used.
// The passphrase remains the backup, exactly as on the web.
(function () {
  try {
    var C = window.Capacitor;
    if (!C || !C.isNativePlatform || !C.isNativePlatform()) return;
    var P = C.Plugins && C.Plugins.DjOpsUnlock;
    if (!P) return;

    function b64(buf) { return btoa(String.fromCharCode.apply(null, new Uint8Array(buf))); }
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
            getClientExtensionResults: function () { return { prf: { enabled: false } }; }
          };
        });
      },
      get: function (opts) {
        if (!opts || !opts.publicKey) return Promise.reject(new Error('Unsupported credential request'));
        return P.unlock().then(function () {
          var id = randBytes(32);
          return {
            id: b64(id), rawId: id.buffer, type: 'public-key',
            response: { authenticatorData: authData(), clientDataJSON: new ArrayBuffer(0), signature: new ArrayBuffer(0) },
            getClientExtensionResults: function () { return {}; }
          };
        });
      }
    };
    Object.defineProperty(navigator, 'credentials', { value: creds, configurable: true });
  } catch (e) { /* leave browser defaults in place */ }
})();
